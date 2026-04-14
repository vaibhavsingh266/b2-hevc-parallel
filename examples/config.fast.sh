#!/bin/bash
# Fast Configuration - Speed prioritized, acceptable quality
# Use this for high-throughput scenarios where speed is critical

export WORKDIR="/mnt/ssd/hevc_fast"
export ENCODE_JOBS=4
export DOWNLOAD_JOBS=8
export MAX_PREFETCH=12

# NVENC Settings - Optimized for speed
export NVENC_PRESET="p7"          # Fastest preset
export NVENC_TUNE="hq"            # Still use high quality tuning
export RC_MODE="vbr"              # Variable bitrate
export CQ_1080="26"               # Lower quality for speed (higher CQ = lower quality)
export CQ_2160="28"               # Lower quality for 4K
export MULTIPASS="disabled"       # Single pass for speed
export SPATIAL_AQ=1               # Keep adaptive quantization
export TEMPORAL_AQ=1              
export AQ_STRENGTH=8              
export FORCE_10BIT=0              # 8-bit encoding for speed
export ALLOW_SW_DECODE_FALLBACK=1
export VERIFY_MODE="exists"       # Just check file exists (faster)

# B2 Settings
export B2_DISABLE_CHECKSUM=1      # Disable checksums for speed

# Other
export DELETE_LOCAL_AFTER_UPLOAD=1

echo "Fast configuration loaded"
echo "  Encode jobs: $ENCODE_JOBS (parallel)"
echo "  Download jobs per part: $DOWNLOAD_JOBS (parallel)"
echo "  Max prefetch: $MAX_PREFETCH"
echo "  NVENC Preset: $NVENC_PRESET (fastest)"
echo "  Quality 1080p: CQ=$CQ_1080 (lower quality for speed)"
echo "  Quality 4K: CQ=$CQ_2160 (lower quality for speed)"
echo "  Multipass: $MULTIPASS (disabled for speed)"
