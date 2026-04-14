#!/bin/bash
# Production Configuration - Balanced performance and quality
# Use this for typical production encoding jobs

export WORKDIR="/workspace/hevc_job"
export ENCODE_JOBS=2
export DOWNLOAD_JOBS=4
export MAX_PREFETCH=8

# NVENC Settings - Balanced quality and speed
export NVENC_PRESET="p5"          # Preset: p5 is good balance
export NVENC_TUNE="hq"            # High quality tuning
export RC_MODE="vbr"              # Variable bitrate for quality
export CQ_1080="22"               # Quality for 1080p (lower = better)
export CQ_2160="24"               # Quality for 4K
export MULTIPASS="qres"           # Two-pass with quarter resolution
export SPATIAL_AQ=1               # Spatial adaptive quantization
export TEMPORAL_AQ=1              # Temporal adaptive quantization
export AQ_STRENGTH=8              # Quantization strength
export FORCE_10BIT=0              # Auto-detect bit depth
export ALLOW_SW_DECODE_FALLBACK=1 # Fallback to software decode if needed
export VERIFY_MODE="size"         # Verify upload by size

# B2 Settings
export B2_DISABLE_CHECKSUM=0      # Enable checksums for integrity

# Other
export DELETE_LOCAL_AFTER_UPLOAD=1

echo "Production configuration loaded"
echo "  Encode jobs: $ENCODE_JOBS"
echo "  Download jobs per part: $DOWNLOAD_JOBS"
echo "  NVENC Preset: $NVENC_PRESET"
echo "  Quality 1080p: CQ=$CQ_1080"
echo "  Quality 4K: CQ=$CQ_2160"
