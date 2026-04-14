# B2 VAST HEVC Parallel Encoder

A high-performance Bash script for batch video encoding to HEVC format using NVIDIA GPU acceleration, with automatic download, encode, and upload workflow from Backblaze B2 cloud storage.

## Overview

**b2_vast_hevc_parallel.sh** is a production-grade video processing pipeline that:
- Downloads video files from Backblaze B2 cloud storage
- Encodes them to HEVC/H.265 format using NVIDIA GPU acceleration (NVENC)
- Uploads the encoded files back to B2 storage
- Processes multiple files in parallel across multiple stages (download → encode → upload)
- Handles failures gracefully with detailed logging
- Provides verification modes to ensure upload integrity

This tool is designed for large-scale video transcoding operations where you have thousands of videos to convert to HEVC format at scale.

## Features

### Core Capabilities
- **GPU-Accelerated Encoding**: Uses NVIDIA NVENC for hardware-based H.265/HEVC encoding, significantly faster than CPU-based encoding
- **Parallel Processing**: Configurable concurrent download, encoding, and upload workers for optimal resource utilization
- **B2 Cloud Storage Integration**: Seamless integration with Backblaze B2 via `rclone` for S3-compatible object storage
- **Intelligent Prefetching**: Maintains a queue of pre-downloaded files ready for encoding to minimize idle GPU time
- **Automatic Fallback**: Falls back to software decoding if hardware decode fails, with optional CUDA encoding still active
- **Quality Preservation**: Supports 10-bit encoding, color space/primaries preservation, and configurable quality levels
- **State Management**: Uses file locks and atomic operations to safely manage concurrent job state
- **Comprehensive Logging**: Detailed per-file logs plus master log for troubleshooting and monitoring
- **Verification**: Multiple verification modes (exists, size) to ensure successful uploads

### Advanced Features
- **Adaptive Quality**: Automatic CQ (constant quality) adjustments based on video resolution (1080p vs 2160p)
- **HDR Support**: Preserves color space, color primaries, and color transfer functions
- **Bit Depth Handling**: Detects and preserves 10-bit content, with optional forced 10-bit encoding
- **Metadata Preservation**: Preserves metadata and chapter information from source files
- **Skip Logic**: Automatically skips files that already exist in the output bucket
- **Self-Test Mode**: Validates GPU setup and encoding pipeline before running production jobs

## Requirements

### System Requirements
- **Linux**: Bash 4.0+ (uses `set -Eeuo pipefail`, `shopt -s nullglob`, and dynamic file descriptors)
- **GPU**: NVIDIA GPU with NVENC support (Maxwell generation or newer)
- **CUDA**: NVIDIA CUDA runtime (for GPU acceleration)

### Software Dependencies
- **FFmpeg**: Must be compiled with NVIDIA NVENC support (`--enable-nvenc`)
- **FFprobe**: Part of FFmpeg suite, used for video stream analysis
- **Rclone**: For cloud storage interactions with Backblaze B2

### Installation
```bash
# Ubuntu/Debian
sudo apt-get install ffmpeg

# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Verify NVENC support
ffmpeg -hide_banner -encoders 2>/dev/null | grep hevc_nvenc

# Verify CUDA
ffmpeg -hide_banner -loglevel error -init_hw_device cuda=gpu:0 -f lavfi -i nullsrc=s=16x16:r=1 -t 0.1 -f null -
```

### Backblaze B2 Configuration
```bash
# Configure rclone for B2
rclone config

# You'll need:
# - B2 Account ID (from B2 Settings → Account page)
# - B2 Application Key (from B2 Settings → Application Keys)
# - Bucket names for source and output

# Test the configuration
rclone ls b2remote:sourcebucket
```

## Configuration

### Hard-Coded Configuration
Edit these variables in the script before first run:

```bash
B2_REMOTE="b2"                    # rclone remote name for B2
B2_SOURCE_BUCKET="source-bucket"  # Source bucket name
B2_OUTPUT_BUCKET="output-bucket"  # Destination bucket name
PARTS=(part2 part3 part4)         # Bucket subdirectories/parts to process
VIDEO_PATTERNS=("*.mp4" "*.mkv")  # File patterns to match
```

### Runtime Environment Variables
Override these via environment variables to customize behavior:

#### Directories
```bash
WORKDIR=/workspace/hevc_job           # Base working directory (default: /workspace/hevc_job)
# Subdirectories created automatically:
#   - spool/      : Temporary storage for files being processed
#   - state/      : Lock files and counters
#   - logs/       : Log files
#   - filelists/  : Lists of files to process per part
#   - tmp/        : Temporary files
```

#### Concurrency
```bash
ENCODE_JOBS=2              # Number of parallel encoding workers (default: 2)
DOWNLOAD_JOBS=3            # Number of parallel download workers per part (default: 3)
MAX_PREFETCH=6             # Maximum queued items before download workers pause (default: 6)
```

Example: Run with more aggressive parallelization
```bash
export ENCODE_JOBS=4
export DOWNLOAD_JOBS=5
export MAX_PREFETCH=10
./b2_vast_hevc_parallel.sh
```

#### Binary Paths
```bash
RCLONE_BIN="/path/to/rclone"       # (default: rclone from PATH)
FFMPEG_BIN="/path/to/ffmpeg"       # (default: ffmpeg from PATH)
FFPROBE_BIN="/path/to/ffprobe"     # (default: ffprobe from PATH)
```

#### Cloud Storage
```bash
B2_DISABLE_CHECKSUM=0              # Disable B2 checksums for speed (0=enabled, 1=disabled)
```

#### NVENC Encoding Parameters
```bash
NVENC_PRESET="p6"                  # Quality preset: p1-p7 (1=slowest/best, 7=fastest)
NVENC_TUNE="hq"                    # Tuning: hq, ll (low latency), lossless
RC_MODE="vbr"                      # Rate control: vbr, cbr, vbr_hq
CQ_1080="22"                       # Constant quality for 1080p content (0-51, lower=better)
CQ_2160="24"                       # Constant quality for 4K content (0-51)
BF="4"                             # Number of B-frames
B_REF_MODE="middle"                # B-frame reference mode: disabled, each, middle
RC_LOOKAHEAD="20"                  # Rate control lookahead frames (0-32)
MULTIPASS="qres"                   # Multipass encoding: disabled, qres, fullres
SPATIAL_AQ="1"                     # Spatial Adaptive Quantization (0=disabled, 1=enabled)
TEMPORAL_AQ="1"                    # Temporal Adaptive Quantization (0=disabled, 1=enabled)
AQ_STRENGTH="8"                    # Adaptive quantization strength (1-15)
FORCE_10BIT=0                      # Force 10-bit encoding (0=auto-detect, 1=force)
ALLOW_SW_DECODE_FALLBACK=1         # Allow fallback to software decoding if CUDA decode fails
```

#### Quality Control
```bash
VERIFY_MODE="size"                 # Verification after upload: exists, size
DELETE_LOCAL_AFTER_UPLOAD=1        # Delete local files after successful upload (1=yes)
```

Example: Configure for high-quality archival encoding
```bash
export NVENC_PRESET="p1"           # Slowest, best quality
export NVENC_TUNE="hq"             # High quality mode
export CQ_1080="20"                # Higher quality for 1080p
export CQ_2160="22"                # Higher quality for 4K
export FORCE_10BIT=1               # Always use 10-bit
./b2_vast_hevc_parallel.sh
```

## Usage

### Basic Usage
```bash
./b2_vast_hevc_parallel.sh
```

This will:
1. Initialize working directories
2. Verify NVIDIA GPU support and CUDA initialization
3. Scan B2 buckets for video files matching `PARTS` and `VIDEO_PATTERNS`
4. Start parallel download workers
5. Start parallel encode/upload workers
6. Process files until all are complete
7. Print summary statistics

### Self-Test Mode
Before running production encodings, test your GPU and setup:

```bash
./b2_vast_hevc_parallel.sh --self-test
```

This:
- Creates a test video file (1280x720, 2 seconds)
- Attempts NVENC encoding if GPU is available
- Falls back to libx265 (software) if GPU is unavailable
- Verifies the output codec is HEVC
- Reports success/failure

Successful output:
```
[2024-04-13T10:30:45Z] Preparing file lists...
[2024-04-13T10:30:47Z] NVENC is usable here, self-test will exercise NVENC
[2024-04-13T10:30:52Z] Self-test passed. Output: /workspace/hevc_job/tmp/selftest_remote/dest/part2/subdir/test.mp4 codec=hevc
```

## Workflow Architecture

### Pipeline Stages

The script implements a three-stage pipeline:

```
┌──────────────┐      ┌────────────┐      ┌──────────────┐
│   Download   │ ───> │   Encode   │ ───> │   Upload     │
│   Workers    │      │   Workers  │      │   Workers    │
└──────────────┘      └────────────┘      └──────────────┘
      │                     │                     │
   Files              Encoded Files            Remote
   Listed             Verified                Storage
```

### Worker Processes

**Download Workers** (DOWNLOAD_JOBS per part):
- Scan remote file lists
- Check if output already exists (skip if yes)
- Download source files to local spool using `rclone copyto`
- Create metadata file with encoding parameters
- Mark files as ready for encoding

**Encode Workers** (ENCODE_JOBS total):
- Poll for ready files from all parts
- Extract video properties (resolution, color space, bit depth)
- Build optimized FFmpeg command based on properties
- Execute encoding (NVENC GPU acceleration)
- Move encoded file to local spool
- Track counters (downloaded, encoded, etc.)

**Upload & Deletion**:
- Upload encoded file to B2 via `rclone copyto`
- Verify upload (exists check or size comparison)
- Delete local copies if verification passes
- Update global counters

### State Management

Files stored in `STATE_DIR/$WORKDIR/state/`:

```
claims/part2/            # One claim file per listed file (prevents duplicate processing)
claims/part2/file.claim  # Created atomically when worker claims a file
downloaded.count         # Counter: files successfully downloaded
done.count              # Counter: files successfully encoded and uploaded
encode_failed.count     # Counter: files that failed encoding
upload_failed.count     # Counter: files that failed upload
verify_failed.count     # Counter: files that failed verification
download_failed.count   # Counter: files that failed download
skipped.count          # Counter: files already existed remotely
```

### Queue Management

Prevents GPU starvation and disk overflow:

```
SPOOL_DIR/$WORKDIR/spool/:
  file.input.mp4           # Downloaded source (awaiting encoding)
  file.ready               # Marker that file is ready to encode
  file.working             # Marker indicating encoding in progress
  file.hevc.mp4            # Encoded output (before upload)
  file.meta                # Metadata about the file (part, paths, etc.)
```

**Prefetch Control**: Download workers pause when `queued_items_count() >= MAX_PREFETCH` to prevent unbounded disk usage.

## Logging

### Log Files Location
All logs stored under `LOG_DIR=$WORKDIR/logs/`:

```
master.log                              # Main script log
download_part2_1.log                    # Download worker 1 for part2
download_part2_2.log                    # Download worker 2 for part2
download_part2_3.log                    # Download worker 3 for part2
encode_1.log                            # Encode/upload worker 1
encode_2.log                            # Encode/upload worker 2
file_part2_subdir_myfile_mp4.log       # Per-file encoding details
```

### Log Entry Format
```
[2024-04-13T10:30:45Z] Command description and details
```

ISO-8601 UTC timestamps with millisecond precision.

### What Gets Logged

**Master log**:
- Worker startup/shutdown
- File list discovery
- Summary statistics
- GPU capability checks
- Self-test results

**Download logs**:
- Downloaded vs skipped files
- Remote paths checked
- Failures with error details

**Encode logs**:
- FFmpeg command executed
- Encoding progress
- Upload paths
- Verification results
- Fallback attempts

**Per-file logs**:
- Complete FFmpeg output
- Performance metrics
- Detailed error messages

## Performance Tuning

### GPU Utilization
- **NVENC_PRESET**: Lower value (p1) = slower but better quality; higher value (p7) = faster but lower quality
  - Recommend `p4` or `p5` for production (good balance)
  - Recommend `p1` or `p2` for archival (maximum quality)

- **RC_MODE**: 
  - `vbr` (Variable Bit Rate) - best quality, variable file size
  - `cbr` (Constant Bit Rate) - fixed bandwidth, may sacrifice quality
  - `vbr_hq` - VBR with two-pass encoding for quality

- **MULTIPASS**:
  - `disabled` - single pass (fastest)
  - `qres` - two-pass with quarter-resolution first pass (medium speed)
  - `fullres` - two-pass full resolution (slowest, best quality)

### Parallel Processing
- **ENCODE_JOBS**: Match to number of GPUs or GPU SM count. Typical: 2-4 for single GPU
- **DOWNLOAD_JOBS**: 3-5 per part works well for B2 (cloud I/O bottleneck)
- **MAX_PREFETCH**: Tune based on local storage capacity. Larger = better GPU utilization but more disk space

Recommendation for single GPU:
```bash
export ENCODE_JOBS=2
export DOWNLOAD_JOBS=4
export MAX_PREFETCH=8
```

### Memory Management
NVENC is very memory-efficient (minimal VRAM usage). Bottleneck is typically:
- Local disk space for decoded and encoded frames
- Network bandwidth to B2

### Quality vs Speed Trade-off
```bash
# Fast (quality ~4/10)
export NVENC_PRESET="p7" CQ_1080="24" CQ_2160="26" MULTIPASS="disabled"

# Balanced (quality ~7/10) - RECOMMENDED
export NVENC_PRESET="p5" CQ_1080="22" CQ_2160="24" MULTIPASS="qres"

# Archival (quality ~9/10)
export NVENC_PRESET="p1" CQ_1080="20" CQ_2160="22" MULTIPASS="fullres" FORCE_10BIT=1
```

## Error Handling

### Common Issues

**Error: "ffmpeg build does not expose hevc_nvenc"**
- FFmpeg not compiled with NVENC support
- Solution: Install FFmpeg with NVENC:
  ```bash
  # Ubuntu using PPA with NVENC support
  sudo apt-add-repository ppa:graphics-drivers/ppa
  sudo apt-get install ffmpeg  # Get pre-built with NVENC
  ```

**Error: "ffmpeg sees hevc_nvenc, but CUDA device init failed"**
- NVIDIA drivers not installed or GPU not detected
- Solution:
  ```bash
  nvidia-smi  # Check if drivers installed
  lspci | grep -i nvidia  # Check if GPU detected
  ```

**DOWNLOAD FAILED / UPLOAD FAILED messages**
- Network issues or B2 credentials
- Check `$LOG_DIR/download_*.log` for rclone error details
- Verify B2 credentials: `rclone lsf b2remote:bucket`

**ENCODE FAILED messages**
- GPU memory exhausted or unsupported pixel format
- Check `$LOG_DIR/file_*.log` for FFmpeg error
- Try with `ALLOW_SW_DECODE_FALLBACK=1` (default)

**VERIFY FAILED messages**
- Upload corruption or network interruption
- File re-uploaded and verified in next retry attempt
- Check size comparison: `rclone lsf`

### Recovery

The script uses atomic operations and claim files to prevent duplicate processing:

- If script crashes, restart with same configuration
- Files being processed are in "working" state (won't be re-claimed)
- Files successfully uploaded won't be re-processed (exist check)
- Counters preserved in state files for accurate statistics

## Examples

### Example 1: Basic Production Run
```bash
#!/bin/bash
export WORKDIR="/workspace/video_encoding"
export ENCODE_JOBS=2
export DOWNLOAD_JOBS=4
export NVENC_PRESET="p5"
export CQ_1080="22"
export CQ_2160="24"

./b2_vast_hevc_parallel.sh
```

### Example 2: High-Quality Archival
```bash
#!/bin/bash
export WORKDIR="/mnt/cache/hevc_archive"
export ENCODE_JOBS=1
export DOWNLOAD_JOBS=2
export NVENC_PRESET="p1"
export MULTIPASS="fullres"
export RC_LOOKAHEAD=32
export FORCE_10BIT=1
export CQ_1080="20"
export CQ_2160="22"

./b2_vast_hevc_parallel.sh
```

### Example 3: High-Throughput (Speed-Prioritized)
```bash
#!/bin/bash
export WORKDIR="/mnt/ssd/hevc_fast"
export ENCODE_JOBS=4
export DOWNLOAD_JOBS=8
export MAX_PREFETCH=12
export NVENC_PRESET="p7"
export MULTIPASS="disabled"
export CQ_1080="26"
export CQ_2160="28"

./b2_vast_hevc_parallel.sh
```

### Example 4: Distributed Processing (Multiple Machines)

Run on machine 1:
```bash
export ENCODE_JOBS=2
./b2_vast_hevc_parallel.sh
```

Run on machine 2 (different DOWNLOAD_JOBS for part3):
```bash
export ENCODE_JOBS=2
./b2_vast_hevc_parallel.sh
```

The claim file system prevents collisions automatically.

## Output and Monitoring

### Real-Time Monitoring
```bash
# Watch master log in real-time
tail -f /workspace/hevc_job/logs/master.log

# Monitor specific worker
tail -f /workspace/hevc_job/logs/encode_1.log

# Check spool queue
ls -l /workspace/hevc_job/spool/*.ready | wc -l

# Monitor counters
cat /workspace/hevc_job/state/*.count
```

### Final Summary
Printed to console and logged:
```
Summary: downloaded=500, skipped=50, done=450, download_failed=0, encode_failed=2, upload_failed=1, verify_failed=0
```

### Performance Metrics
- **Files/minute**: done / (elapsed_time_minutes)
- **Throughput**: File size / encoding_duration
- **Queue depth**: queued_items_count() / MAX_PREFETCH
- **GPU utilization**: Visible in `nvidia-smi`

## Technical Details

### FFmpeg Build Command
The script uses this FFmpeg pipeline structure:
```
Input (H.264, H.265, ProRes, etc.)
  ↓
Hardware Decode (CUDA)
  ↓ (with fallback to software decode)
Video Encode (HEVC_NVENC)
Audio Copy (bit-for-bit from source)
Metadata Preservation
  ↓
Output (HEVC/H.265 in MP4/MKV container)
```

### Pixel Format Handling
- Input: Auto-detected (yuv420p, p010le, etc.)
- Processing: Native GPU codec format
- Output: 
  - 8-bit: `yuv420p` (8-bit HDR or SDR)
  - 10-bit: `p010le` (10-bit HDR)

### Color Space Preservation
Script extracts and re-applies:
- **Color Space**: bt709, bt2020, etc.
- **Color Primaries**: bt709, bt2020, etc.
- **Transfer Function**: bt709, smpte2084 (PQ for HDR), etc.

### Concurrency Model
- Each worker is a background Bash process (spawned with `&`)
- Main script waits for all with `wait` builtin
- Lock files (flock) protect counter and claim operations
- Atomic file operations (rename, create with noclobber) prevent races

## Troubleshooting

### Debug Mode
Enable more verbose logging:
```bash
# View FFmpeg debug output for a file
tail -f /workspace/hevc_job/logs/file_*.log | grep -A 10 "Command:"

# View rclone debug (add to RCLONE_FLAGS in script)
# RCLONE_FLAGS+=(-vv)  # Very verbose
```

### Test with Sample File
```bash
./b2_vast_hevc_parallel.sh --self-test
echo "Exit code: $?"
```

If self-test fails, production run will also fail.

### Check GPU Health
```bash
nvidia-smi
nvidia-smi -l 1  # Show stats every 1 second
nvidia-smi --query-gpu=name,memory.used,memory.max,utilization.gpu,utilization.memory --format=csv,noheader -l 1
```

## Security Considerations

1. **B2 Credentials**: Stored in `~/.config/rclone/rclone.conf` - protect with appropriate file permissions
2. **Local Files**: Temporary spool and encoded files stored in `WORKDIR` - ensure disk encryption if sensitive
3. **Logs**: Contain full file paths and B2 bucket names - protect log directory access
4. **Authentication**: Uses rclone's credential system - use application keys instead of master B2 credentials

## License and Attribution

This script is provided as-is for video encoding workflows using NVIDIA GPUs and Backblaze B2 storage.

## Support and Contribution

For issues or improvements:
1. Check logs in `$WORKDIR/logs/master.log`
2. Run self-test: `./b2_vast_hevc_parallel.sh --self-test`
3. Review FFmpeg encoder support: `ffmpeg -hide_banner -encoders | grep hevc`

## Related Tools

- **FFmpeg**: https://ffmpeg.org/
- **Rclone**: https://rclone.org/
- **Backblaze B2**: https://www.backblaze.com/b2/cloud-storage.html
- **NVIDIA NVENC Documentation**: https://docs.nvidia.com/video-technologies/video-codec-sdk/

## Appendix: Quality Recommendations

| Use Case | Preset | Tune | RC_MODE | CQ 1080 | CQ 2160 | Multipass | 10-bit |
|----------|--------|------|---------|---------|---------|-----------|--------|
| Streaming | p7 | ll | cbr | 26 | 28 | disabled | 0 |
| Fast Copy | p7 | hq | vbr | 24 | 26 | disabled | 0 |
| Balanced | p5 | hq | vbr | 22 | 24 | qres | 0 |
| Archival | p1 | hq | vbr_hq | 20 | 22 | fullres | 1 |
| High-Quality | p2 | hq | vbr_hq | 20 | 21 | fullres | 1 |

(Lower CQ = higher quality, ~0.5-1 CQ difference ≈ ~5-10% file size difference)
