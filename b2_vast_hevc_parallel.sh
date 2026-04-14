#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

FFMPEG_BIN="/usr/bin/ffmpeg"
FFPROBE_BIN="/usr/bin/ffprobe"

# Hard-coded configuration
B2_REMOTE=""
B2_SOURCE_BUCKET=""
B2_OUTPUT_BUCKET=""
PARTS=(part2 part3 part4)
VIDEO_PATTERNS=("*.mp4" "*.mkv")

# Runtime settings
WORKDIR="${WORKDIR:-/workspace/hevc_job}"
SPOOL_DIR="$WORKDIR/spool"
STATE_DIR="$WORKDIR/state"
LOG_DIR="$WORKDIR/logs"
FILELIST_DIR="$WORKDIR/filelists"
TMP_DIR="$WORKDIR/tmp"
MASTER_LOG="$LOG_DIR/master.log"
LOCK_FILE="$STATE_DIR/global.lock"

RCLONE_BIN="${RCLONE_BIN:-rclone}"
FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"
FFPROBE_BIN="${FFPROBE_BIN:-ffprobe}"

# Concurrency
ENCODE_JOBS="${ENCODE_JOBS:-2}"
DOWNLOAD_JOBS="${DOWNLOAD_JOBS:-3}"
MAX_PREFETCH="${MAX_PREFETCH:-6}"

# rclone settings
B2_DISABLE_CHECKSUM="${B2_DISABLE_CHECKSUM:-0}"
RCLONE_FLAGS=(--stats=30s --stats-one-line --retries=5 --low-level-retries=20 --contimeout=60s --timeout=0)

# Encoder settings
NVENC_PRESET="${NVENC_PRESET:-p6}"
NVENC_TUNE="${NVENC_TUNE:-hq}"
RC_MODE="${RC_MODE:-vbr}"
CQ_1080="${CQ_1080:-22}"
CQ_2160="${CQ_2160:-24}"
BF="${BF:-4}"
B_REF_MODE="${B_REF_MODE:-middle}"
RC_LOOKAHEAD="${RC_LOOKAHEAD:-20}"
MULTIPASS="${MULTIPASS:-qres}"
SPATIAL_AQ="${SPATIAL_AQ:-1}"
TEMPORAL_AQ="${TEMPORAL_AQ:-1}"
AQ_STRENGTH="${AQ_STRENGTH:-8}"
FORCE_10BIT="${FORCE_10BIT:-0}"
ALLOW_SW_DECODE_FALLBACK="${ALLOW_SW_DECODE_FALLBACK:-1}"
VERIFY_MODE="${VERIFY_MODE:-size}"
DELETE_LOCAL_AFTER_UPLOAD="1"

SELFTEST_MODE="0"
LOCAL_TEST_ROOT=""

cleanup() {
  local code=$?
  if [[ $code -ne 0 ]]; then
    log "Script exited with code $code"
  fi
}
trap cleanup EXIT

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 127; }; }

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { mkdir -p "$LOG_DIR"; echo "[$(ts)] $*" | tee -a "$MASTER_LOG" >&2; }

init_dirs() {
  rm -rf "$SPOOL_DIR" "$STATE_DIR" "$LOG_DIR" "$FILELIST_DIR" "$TMP_DIR"
  mkdir -p "$WORKDIR" "$SPOOL_DIR" "$STATE_DIR" "$LOG_DIR" "$FILELIST_DIR" "$TMP_DIR"
  : > "$MASTER_LOG"
}

with_lock() {
  local fd=200
  exec {fd}>"$LOCK_FILE"
  flock -x "$fd"
  "$@"
  local rc=$?
  flock -u "$fd"
  eval "exec ${fd}>&-"
  return $rc
}

inc_counter() {
  local name="$1"
  local file="$STATE_DIR/${name}.count"
  mkdir -p "$STATE_DIR"
  (
    flock -x 200
    local n=0
    [[ -f "$file" ]] && read -r n < "$file" || true
    echo $((n+1)) > "$file"
  ) 200>"$LOCK_FILE"
}

set_counter() {
  local name="$1" value="$2"
  local file="$STATE_DIR/${name}.count"
  (
    flock -x 200
    echo "$value" > "$file"
  ) 200>"$LOCK_FILE"
}

get_counter() {
  local name="$1"
  local file="$STATE_DIR/${name}.count"
  [[ -f "$file" ]] && cat "$file" || echo 0
}

remote_file_exists() {
  local remote_file="$1"
  local remote_dir remote_base out
  remote_dir=$(dirname "$remote_file")
  remote_base=$(basename "$remote_file")
  out=$("$RCLONE_BIN" lsf "$remote_dir" --files-only --include "$remote_base" 2>/dev/null || true)
  out=${out%$'\n'}
  [[ "$out" == "$remote_base" ]]
}

remote_file_size_bytes() {
  local remote_file="$1"
  local remote_dir remote_base sep out size name
  remote_dir=$(dirname "$remote_file")
  remote_base=$(basename "$remote_file")
  sep=$'\t'
  out=$("$RCLONE_BIN" lsf "$remote_dir" --files-only --include "$remote_base" --format "sp" --separator "$sep" 2>/dev/null || true)
  out=${out%$'\n'}
  [[ -n "$out" ]] || return 1
  size=${out%%$sep*}
  name=${out#*$sep}
  [[ "$name" == "$remote_base" ]] || return 1
  [[ "$size" =~ ^[0-9]+$ ]] || return 1
  echo "$size"
}

rclone_copyto() {
  local src="$1" dst="$2"
  local extra=()
  [[ "$B2_DISABLE_CHECKSUM" == "1" ]] && extra+=(--b2-disable-checksum)
  "$RCLONE_BIN" copyto "$src" "$dst" "${RCLONE_FLAGS[@]}" "${extra[@]}"
}

ffmpeg_has_nvenc() {
  local encoders
  encoders=$("$FFMPEG_BIN" -hide_banner -encoders 2>/dev/null || true)
  if echo "$encoders" | grep -Fq 'hevc_nvenc'; then
    return 0
  fi
  echo "$encoders" >> "$MASTER_LOG"
  return 1
}

ffmpeg_can_init_cuda() {
  "$FFMPEG_BIN" -hide_banner -loglevel error -init_hw_device cuda=gpu:0 -f lavfi -i nullsrc=s=16x16:r=1 -t 0.1 -f null - >/dev/null 2>&1
}

probe_field() {
  local input="$1" field="$2"
  "$FFPROBE_BIN" -v error -select_streams v:0 -show_entries "stream=${field}" -of default=nw=1:nk=1 "$input" 2>/dev/null | head -n1
}

is_10bit_pixfmt() {
  local pf="$1"
  [[ "$pf" == *10* || "$pf" == p010le || "$pf" == p016le ]]
}

make_rel_safe() { echo "$1" | sed 's#[/\\]#_#g'; }

build_ffmpeg_cmd() {
  local input_path="$1" output_path="$2"
  local width height pix_fmt csp cpr ctr cq want_10bit profile out_pix_fmt
  width=$(probe_field "$input_path" width || true)
  height=$(probe_field "$input_path" height || true)
  pix_fmt=$(probe_field "$input_path" pix_fmt || true)
  csp=$(probe_field "$input_path" color_space || true)
  cpr=$(probe_field "$input_path" color_primaries || true)
  ctr=$(probe_field "$input_path" color_transfer || true)
  cq="$CQ_1080"
  [[ -n "$height" && "$height" =~ ^[0-9]+$ && "$height" -ge 1600 ]] && cq="$CQ_2160"

  want_10bit=0
  if [[ "$FORCE_10BIT" == "1" ]] || is_10bit_pixfmt "$pix_fmt"; then want_10bit=1; fi
  profile="main"; out_pix_fmt="yuv420p"
  if [[ "$want_10bit" == "1" ]]; then profile="main10"; out_pix_fmt="p010le"; fi

  local color_args=()
  [[ -n "$csp" && "$csp" != "unknown" && "$csp" != "N/A" ]] && color_args+=( -colorspace "$csp" )
  [[ -n "$cpr" && "$cpr" != "unknown" && "$cpr" != "N/A" ]] && color_args+=( -color_primaries "$cpr" )
  [[ -n "$ctr" && "$ctr" != "unknown" && "$ctr" != "N/A" ]] && color_args+=( -color_trc "$ctr" )

  printf '%s\0' \
    "$FFMPEG_BIN" -y -hwaccel cuda -hwaccel_output_format cuda -i "$input_path" \
    -fps_mode passthrough -map 0:V:0 -map 0:a? -map_metadata 0 -map_chapters 0 \
    -c:v hevc_nvenc -preset "$NVENC_PRESET" -tune "$NVENC_TUNE" -rc "$RC_MODE" \
    -cq "$cq" -b:v 0 -profile:v "$profile" -pix_fmt "$out_pix_fmt" \
    "${color_args[@]}" -b_ref_mode "$B_REF_MODE" -spatial_aq "$SPATIAL_AQ" -temporal_aq "$TEMPORAL_AQ" \
    -aq-strength "$AQ_STRENGTH" -bf "$BF" -rc-lookahead "$RC_LOOKAHEAD" -multipass "$MULTIPASS" \
    -c:a copy -movflags +faststart "$output_path"
}

encode_one() {
  local input_path="$1" output_path="$2" file_log="$3"
  local -a cmd=()
  while IFS= read -r -d '' token; do cmd+=("$token"); done < <(build_ffmpeg_cmd "$input_path" "$output_path")
  {
    echo "[$(ts)] Input: $input_path"
    echo "[$(ts)] Output: $output_path"
    printf '[%s] Command:' "$(ts)"; printf ' %q' "${cmd[@]}"; printf '\n'
  } >> "$file_log"

  if "${cmd[@]}" >> "$file_log" 2>&1; then
    return 0
  fi

  if [[ "$ALLOW_SW_DECODE_FALLBACK" != "1" ]]; then
    return 1
  fi

  local -a fallback=("$FFMPEG_BIN" -y -i "$input_path" -fps_mode passthrough -map 0:V:0 -map 0:a? -map_metadata 0 -map_chapters 0 -c:v hevc_nvenc -preset "$NVENC_PRESET" -tune "$NVENC_TUNE" -rc "$RC_MODE" -cq "$CQ_1080" -b:v 0 -c:a copy -movflags +faststart "$output_path")
  {
    echo "[$(ts)] CUDA decode path failed, retrying with software decode"
    printf '[%s] Fallback:' "$(ts)"; printf ' %q' "${fallback[@]}"; printf '\n'
  } >> "$file_log"
  "${fallback[@]}" >> "$file_log" 2>&1
}

list_remote_part() {
  local part="$1" list_file="$FILELIST_DIR/${part}.txt"
  : > "$list_file"
  for pattern in "${VIDEO_PATTERNS[@]}"; do
    "$RCLONE_BIN" lsf "${B2_REMOTE}:${B2_SOURCE_BUCKET}${part}" -R --files-only --include "$pattern" >> "$list_file" 2>> "$MASTER_LOG" || true
  done
  awk 'NF' "$list_file" | sort -u > "${list_file}.tmp"
  mv "${list_file}.tmp" "$list_file"
  echo "$list_file"
}

queued_items_count() {
  find "$SPOOL_DIR" -type f -name '*.ready' | wc -l | tr -d ' '
}

claim_list_item() {
  local list_file="$1"
  local claim_dir="$STATE_DIR/claims/$(basename "$list_file" .txt)"
  mkdir -p "$claim_dir"
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    local safe claim
    safe=$(make_rel_safe "$rel")
    claim="$claim_dir/${safe}.claim"
    if ( set -o noclobber; : > "$claim" ) 2>/dev/null; then
      echo "$rel"
      return 0
    fi
  done < "$list_file"
  return 1
}

download_worker_for_part() {
  local part="$1" list_file="$2" worker_id="$3"
  local worker_log="$LOG_DIR/download_${part}_${worker_id}.log"
  while true; do
    while [[ $(queued_items_count) -ge $MAX_PREFETCH ]]; do sleep 2; done
    local rel
    if ! rel=$(claim_list_item "$list_file"); then
      echo "[$(ts)] No more files to claim for $part" >> "$worker_log"
      return 0
    fi

    local src="${B2_REMOTE}:${B2_SOURCE_BUCKET}${part}/${rel}"
    local dst_remote="${B2_REMOTE}:${B2_OUTPUT_BUCKET}${part}/${rel}"
    local safe spool_prefix ext local_input meta
    safe=$(make_rel_safe "$part/$rel")
    ext="${rel##*.}"
    spool_prefix="$SPOOL_DIR/${safe}"
    local_input="${spool_prefix}.input.${ext}"
    meta="${spool_prefix}.meta"

    if remote_file_exists "$dst_remote"; then
      echo "[$(ts)] SKIP remote exists $dst_remote" >> "$worker_log"
      inc_counter skipped
      continue
    fi

    echo "[$(ts)] DOWNLOAD $src -> $local_input" >> "$worker_log"
    if rclone_copyto "$src" "$local_input" >> "$worker_log" 2>&1; then
      {
        printf 'PART=%q\n' "$part"
        printf 'REL=%q\n' "$rel"
        printf 'INPUT=%q\n' "$local_input"
        printf 'OUTPUT_REMOTE=%q\n' "$dst_remote"
        printf 'SAFE=%q\n' "$safe"
      } > "$meta"
      touch "${spool_prefix}.ready"
      inc_counter downloaded
    else
      echo "[$(ts)] DOWNLOAD FAILED $src" >> "$worker_log"
      rm -f "$local_input" "$meta" "${spool_prefix}.ready"
      inc_counter download_failed
    fi
  done
}

claim_ready_item() {
  local ready
  for ready in "$SPOOL_DIR"/*.ready; do
    [[ -e "$ready" ]] || return 1
    local working="${ready%.ready}.working"
    if mv "$ready" "$working" 2>/dev/null; then
      echo "$working"
      return 0
    fi
  done
  return 1
}

all_downloaders_done() {
  local total expected
  expected=0
  for part in "${PARTS[@]}"; do
    [[ -f "$FILELIST_DIR/${part}.txt" ]] || continue
    expected=$(( expected + $(wc -l < "$FILELIST_DIR/${part}.txt") ))
  done
  total=$(( $(get_counter downloaded) + $(get_counter download_failed) + $(get_counter skipped) ))
  [[ "$total" -ge "$expected" ]]
}

encode_upload_worker() {
  local worker_id="$1"
  local worker_log="$LOG_DIR/encode_${worker_id}.log"
  while true; do
    local working
    if ! working=$(claim_ready_item); then
      if all_downloaders_done; then
        echo "[$(ts)] No more work, encoder worker $worker_id exiting" >> "$worker_log"
        return 0
      fi
      sleep 2
      continue
    fi

    local prefix="${working%.working}" meta file_log part rel input_local output_remote safe ext output_local_tmp output_local final_remote_size local_size
    meta="${prefix}.meta"
    source "$meta"
    file_log="$LOG_DIR/file_${SAFE}.log"
    ext="${REL##*.}"
    output_local_tmp="${prefix}.hevc.${ext}.partial"
    output_local="${prefix}.hevc.${ext}"

    echo "[$(ts)] START encode worker=$worker_id file=$REL part=$PART" | tee -a "$worker_log" >> "$file_log"
    if ! encode_one "$INPUT" "$output_local_tmp" "$file_log"; then
      echo "[$(ts)] ENCODE FAILED $INPUT" | tee -a "$worker_log" >> "$file_log"
      rm -f "$working" "$output_local_tmp"
      inc_counter encode_failed
      continue
    fi

    mv -f "$output_local_tmp" "$output_local"
    echo "[$(ts)] UPLOAD $output_local -> $OUTPUT_REMOTE" | tee -a "$worker_log" >> "$file_log"
    if ! rclone_copyto "$output_local" "$OUTPUT_REMOTE" >> "$file_log" 2>&1; then
      echo "[$(ts)] UPLOAD FAILED $OUTPUT_REMOTE" | tee -a "$worker_log" >> "$file_log"
      rm -f "$working"
      inc_counter upload_failed
      continue
    fi

    case "$VERIFY_MODE" in
      exists)
        remote_file_exists "$OUTPUT_REMOTE"
        ;;
      size)
        local_size=$(stat -c%s "$output_local" 2>/dev/null || wc -c < "$output_local")
        final_remote_size=$(remote_file_size_bytes "$OUTPUT_REMOTE" || true)
        [[ -n "$final_remote_size" && "$final_remote_size" == "$local_size" ]]
        ;;
      *)
        echo "Unknown VERIFY_MODE=$VERIFY_MODE" >> "$file_log"
        false
        ;;
    esac

    if [[ $? -ne 0 ]]; then
      echo "[$(ts)] VERIFY FAILED $OUTPUT_REMOTE" | tee -a "$worker_log" >> "$file_log"
      rm -f "$working"
      inc_counter verify_failed
      continue
    fi

    echo "[$(ts)] SUCCESS $OUTPUT_REMOTE" | tee -a "$worker_log" >> "$file_log"
    inc_counter done

    if [[ "$DELETE_LOCAL_AFTER_UPLOAD" == "1" ]]; then
      rm -f "$INPUT" "$output_local" "$meta" "$working"
    fi
  done
}

print_summary() {
  log "Summary: downloaded=$(get_counter downloaded), skipped=$(get_counter skipped), done=$(get_counter done), download_failed=$(get_counter download_failed), encode_failed=$(get_counter encode_failed), upload_failed=$(get_counter upload_failed), verify_failed=$(get_counter verify_failed)"
}

local_self_test() {
  init_dirs
  local src_root="$TMP_DIR/selftest_remote/source"
  local dst_root="$TMP_DIR/selftest_remote/dest"
  mkdir -p "$src_root/part2/subdir" "$dst_root/part2/subdir"

  "$FFMPEG_BIN" -hide_banner -y -f lavfi -i testsrc2=size=1280x720:rate=30 -f lavfi -i sine=frequency=1000:sample_rate=48000 -t 2 -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac "$src_root/part2/subdir/test.mp4" >/dev/null 2>&1

  local input="$src_root/part2/subdir/test.mp4"
  local output="$dst_root/part2/subdir/test.mp4"
  local log_file="$LOG_DIR/selftest_file.log"

  if ffmpeg_has_nvenc && ffmpeg_can_init_cuda; then
    log "NVENC is usable here, self-test will exercise NVENC"
    if ! encode_one "$input" "$output" "$log_file"; then
      echo "Self-test failed during NVENC encode" >&2
      return 1
    fi
  else
    log "NVENC is not usable in this environment, self-test will validate the command shape with libx265 fallback only"
    "$FFMPEG_BIN" -y -i "$input" -map 0:v:0 -map 0:a:0 -c:v libx265 -preset medium -crf 28 -c:a copy -movflags +faststart "$output" >> "$log_file" 2>&1
  fi

  [[ -f "$output" ]] || { echo "Self-test failed, missing output" >&2; return 1; }
  local codec
  codec=$("$FFPROBE_BIN" -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$output" | head -n1)
  [[ "$codec" == "hevc" ]] || { echo "Self-test failed, codec=$codec" >&2; return 1; }
  log "Self-test passed. Output: $output codec=$codec"
}

run_remote() {
  require_cmd "$RCLONE_BIN"
  require_cmd "$FFMPEG_BIN"
  require_cmd "$FFPROBE_BIN"
  init_dirs

  if ! ffmpeg_has_nvenc; then
    echo "ffmpeg build does not expose hevc_nvenc" >&2
    exit 3
  fi

  if ! ffmpeg_can_init_cuda; then
    echo "ffmpeg sees hevc_nvenc, but CUDA device init failed" >&2
    nvidia-smi >&2 || true
    exit 4
  fi

  log "Preparing file lists. Only part2, part3, part4 are scanned. Root bucket files are ignored."
  local part list_file total=0
  for part in "${PARTS[@]}"; do
    list_file=$(list_remote_part "$part")
    local count
    count=$(wc -l < "$list_file" | tr -d ' ')
    total=$((total + count))
    log "Found $count candidate files under ${B2_REMOTE}:${B2_SOURCE_BUCKET}${part}"
  done
  set_counter expected "$total"
  log "Total candidate files across parts: $total"

  for part in "${PARTS[@]}"; do
    local list="$FILELIST_DIR/${part}.txt"
    for i in $(seq 1 "$DOWNLOAD_JOBS"); do
      download_worker_for_part "$part" "$list" "$i" &
    done
  done

  for i in $(seq 1 "$ENCODE_JOBS"); do
    encode_upload_worker "$i" &
  done

  wait
  print_summary
}

main() {
  case "${1:-}" in
    --self-test)
      init_dirs
      local_self_test
      ;;
    "")
      run_remote
      ;;
    *)
      echo "Usage: $0 [--self-test]" >&2
      exit 2
      ;;
  esac
}

main "$@"
