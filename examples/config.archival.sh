#!/bin/bash
# Archival Configuration - Maximum quality preservation
# Use this for high-quality archival encoding, master file preservation

export WORKDIR="/mnt/cache/hevc_archive"
export ENCODE_JOBS=1              # Single encoder for consistency
export DOWNLOAD_JOBS=2            # Limited parallelism for reliability
export MAX_PREFETCH=4             # Conservative queueing

# NVENC Settings - Maximum quality
export NVENC_PRESET="p1"          # Slowest, highest quality
export NVENC_TUNE="hq"            # High quality
export RC_MODE="vbr_hq"           # VBR with high quality mode
export CQ_1080="20"               # High quality for 1080p
export CQ_2160="22"               # High quality for 4K
export MULTIPASS="fullres"        # Two-pass full resolution (best quality)
export SPATIAL_AQ=1               # Enable spatial adaptive quantization
export TEMPORAL_AQ=1              # Enable temporal adaptive quantization
export AQ_STRENGTH=15             # Maximum quantization strength
export BF=4                       # More B-frames for quality
export RC_LOOKAHEAD=32            # Maximum lookahead
export FORCE_10BIT=1              # Force 10-bit for all content
export ALLOW_SW_DECODE_FALLBACK=1
export VERIFY_MODE="size"         # Strict verification

# B2 Settings
export B2_DISABLE_CHECKSUM=0      # Enable checksums for archival integrity

# Other
export DELETE_LOCAL_AFTER_UPLOAD=0  # Keep local copies for backup

echo "Archival configuration loaded"
echo "  Encode jobs: $ENCODE_JOBS (single for consistency)"
echo "  Download jobs per part: $DOWNLOAD_JOBS (conservative)"
echo "  NVENC Preset: $NVENC_PRESET (maximum quality)"
echo "  Quality 1080p: CQ=$CQ_1080 (maximum)"
echo "  Quality 4K: CQ=$CQ_2160 (maximum)"
echo "  Multipass: $MULTIPASS (full resolution)"
echo "  Force 10-bit: $FORCE_10BIT (preserve bit depth)"
echo "  LOCAL COPIES RETAINED: $DELETE_LOCAL_AFTER_UPLOAD (disabled)"
