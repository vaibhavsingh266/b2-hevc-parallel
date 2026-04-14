# Performance Tuning Guide

This guide explains how to optimize `b2-hevc-parallel` for your specific workload and hardware.

## Hardware Considerations

### GPU Memory
NVENC is very memory-efficient. Most NVIDIA GPUs have sufficient VRAM for encoding:
- **Maxwell (GTX 750+, GTX 960+)**: 1-2GB VRAM
- **Pascal (GTX 1050+, GTX 1080+)**: 2-8GB VRAM
- **Turing (RTX 2060+, RTX 2080+)**: 4-11GB VRAM
- **Ampere (RTX 3060+, RTX 3090+)**: 6-24GB VRAM

Typical HEVC encoding uses 30-500MB VRAM, so VRAM is rarely the bottleneck.

### Storage I/O
Local disk I/O is the critical factor:
```bash
# Check disk speed
sudo fio --name=randread --ioengine=libaio --iodepth=16 \
  --rw=randread --bs=4k --direct=1 --size=1G \
  --filename=/path/to/workdir/test.fio

# SSD: >1000 MB/s sustained I/O
# HDD: 50-150 MB/s sustained I/O
```

**Recommendations:**
- Use **NVMe SSD** when possible (throughput 1-7 GB/s)
- Use **SATA SSD** if necessary (throughput 300-550 MB/s)
- Avoid HDDs if encoding HD content (very slow, prevents GPU utilization)
- Ensure enough free space for 1-2 full encoded video sets

### Network Bandwidth
B2 upload/download speeds depend on internet connection:
```bash
# Test B2 speed
rclone -vv --stats=5s copy local_file b2:test-bucket/
```

**Typical speeds:**
- Residential: 10-100 MB/s
- Datacenter: 100-1000 MB/s

## Tuning Parameters

### 1. Parallel Worker Configuration

**ENCODE_JOBS** - Number of parallel encoding workers
```bash
# For single GPU:
# Maxwell (1 GPU SM unit): 1-2
# Pascal (2-4 GPU SM units): 1-2
# Turing (4-8 GPU SM units): 2-4
# Ampere (8-16 GPU SM units): 2-4

export ENCODE_JOBS=2  # Standard single GPU setup

# Multi-GPU (multiple physical GPUs):
# Set ENCODE_JOBS = number_of_gpus * 2
export ENCODE_JOBS=4  # For 2 GPUs
```

**DOWNLOAD_JOBS** - Parallel download workers per part
```bash
# Bottleneck is usually network, not disk
# B2 rate limits: ~50-100 requests/second per account

export DOWNLOAD_JOBS=3  # Conservative (3-5 typical)
export DOWNLOAD_JOBS=8  # Aggressive (for fast networks)
```

**MAX_PREFETCH** - Maximum queued files ready for encoding
```bash
# Controls disk usage during encoding phase
# Higher = better GPU utilization (more files queued)
# Lower = less disk space needed

# Calculate: MAX_PREFETCH = (Available_Disk_GB * 0.8) / Avg_Video_Size_GB
# Example: 500GB disk, avg 2GB video = (500 * 0.8) / 2 = 200

export MAX_PREFETCH=6   # Conservative (use ~12 GB disk)
export MAX_PREFETCH=10  # Moderate (use ~20 GB disk)
export MAX_PREFETCH=20  # Aggressive (use CPU prefetch time for GPU)
```

### 2. Quality vs Speed Trade-offs

#### NVENC_PRESET
Controls encoding speed and quality relationship:
```bash
# p1 (slowest, best quality)
export NVENC_PRESET="p1"  # 10% of p7 speed, ~perceptibly best quality

# p3 (slow, high quality)
export NVENC_PRESET="p3"  # 30% of p7 speed

# p5 (balanced) -- RECOMMENDED
export NVENC_PRESET="p5"  # 60% of p7 speed (good balance)

# p7 (fastest)
export NVENC_PRESET="p7"  # Baseline speed

# Approximate speed ratios:
# Speed = p7 / (10 - preset) approximately
# p1 ≈ 10 files/hour
# p5 ≈ 60 files/hour
# p7 ≈ 100 files/hour
```

#### CQ (Constant Quality) Values
Lower = higher quality, larger file size:
```bash
# CQ value ranges: 0-51 (0=lossless, 51=lowest quality)

# 1080p content
export CQ_1080="22"   # Balanced (recommended)
export CQ_1080="20"   # High quality (archive)
export CQ_1080="24"   # Lower quality (streaming)

# 4K content  
export CQ_2160="24"   # Balanced (recommended)
export CQ_2160="22"   # High quality (archive)
export CQ_2160="26"   # Lower quality (streaming)

# Quality equivalents:
# ΔCQ ±1 ≈ ±5% file size / ±~0.5dB PSNR
# ΔCQ ±3 ≈ ±15% file size / ±~1dB PSNR
```

### 3. Multipass Encoding

Controls encoding passes and quality:
```bash
export MULTIPASS="disabled"   # Single pass (fastest, slightly lower quality)
export MULTIPASS="qres"       # Two-pass with 1/4 resolution (balanced - RECOMMENDED)
export MULTIPASS="fullres"    # Two-pass full resolution (slowest, best quality)

# Speed impact:
# disabled     ≈ baseline
# qres         ≈ 1.3-1.5x slower than disabled
# fullres      ≈ 2-3x slower than disabled
```

### 4. Rate Control Mode

Different rate control strategies:
```bash
export RC_MODE="vbr"          # Variable bitrate (quality priority - RECOMMENDED)
export RC_MODE="cbr"          # Constant bitrate (bandwidth priority)
export RC_MODE="vbr_hq"       # VBR high quality (requires fullres multipass)

# VBR:      Best quality, variable file size
# CBR:      Fixed bandwidth, consistent quality
# VBR_HQ:   Best quality (use with MULTIPASS="fullres")
```

### 5. Adaptive Quantization

Fine-tune quality enhancement:
```bash
export SPATIAL_AQ=1            # Spatial adaptive quantization (preserve details)
export TEMPORAL_AQ=1           # Temporal adaptive quantization (smooth transitions)
export AQ_STRENGTH=8           # Quantization strength (1-15)

# For video with high detail:
export AQ_STRENGTH=15          # Maximum strength

# For smooth/simple content:
export AQ_STRENGTH=4           # Lower strength (faster)
```

## Tuning Profiles

### Profile 1: Maximum Throughput
```bash
export ENCODE_JOBS=4
export DOWNLOAD_JOBS=8
export MAX_PREFETCH=20
export NVENC_PRESET="p7"
export MULTIPASS="disabled"
export CQ_1080="26"
export CQ_2160="28"
export SPATIAL_AQ=1
export TEMPORAL_AQ=0            # Disable for speed
export VERIFY_MODE="exists"     # Faster verification

# Expected: ~100 files/hour on single GPU
```

### Profile 2: Balanced (RECOMMENDED)
```bash
export ENCODE_JOBS=2
export DOWNLOAD_JOBS=4
export MAX_PREFETCH=8
export NVENC_PRESET="p5"
export MULTIPASS="qres"
export CQ_1080="22"
export CQ_2160="24"
export SPATIAL_AQ=1
export TEMPORAL_AQ=1
export VERIFY_MODE="size"

# Expected: ~30-40 files/hour on single GPU
# File size reduction: ~50-60% vs original
```

### Profile 3: High Quality
```bash
export ENCODE_JOBS=2
export DOWNLOAD_JOBS=3
export MAX_PREFETCH=6
export NVENC_PRESET="p3"
export MULTIPASS="fullres"
export CQ_1080="20"
export CQ_2160="22"
export SPATIAL_AQ=1
export TEMPORAL_AQ=1
export AQ_STRENGTH=12
export VERIFY_MODE="size"

# Expected: ~8-12 files/hour on single GPU
# File size reduction: ~70-80% vs original
```

### Profile 4: Archival (Maximum Quality)
```bash
export ENCODE_JOBS=1
export DOWNLOAD_JOBS=2
export MAX_PREFETCH=4
export NVENC_PRESET="p1"
export MULTIPASS="fullres"
export RC_MODE="vbr_hq"
export CQ_1080="20"
export CQ_2160="21"
export FORCE_10BIT=1
export SPATIAL_AQ=1
export TEMPORAL_AQ=1
export AQ_STRENGTH=15
export RC_LOOKAHEAD=32
export VERIFY_MODE="size"

# Expected: ~3-5 files/hour on single GPU
# File size reduction: ~75-85% vs original
# Maximum quality preservation for archival
```

## Optimization Techniques

### 1. Monitor GPU Utilization
```bash
# Monitor in real-time
nvidia-smi dmon

# Or with watch
watch -n 1 'nvidia-smi | grep -E "GPU|Processes" -A 20'

# Or every 5 seconds with high detail
nvidia-smi --query-gpu=timestamp,name,memory.used,memory.max,utilization.gpu,utilization.memory \
  --format=csv,noheader -l 5
```

**Target GPU utilization: 85-100%**
- If < 80%: Increase `ENCODE_JOBS` or `MAX_PREFETCH`
- If > 95%: May indicate bottleneck elsewhere

### 2. Monitor Network I/O
```bash
# During encode/upload
nethogs

# Or check specific process
iftop -n
```

### 3. Monitor Disk I/O
```bash
# Check disk utilization
iostat -x 1

# Check specific directory
du -sh /workspace/hevc_job/spool
```

### 4. Profile Encoding Performance
```bash
# Encode a single file with timing
time ./b2_vast_hevc_parallel.sh --self-test

# Extract speed from logs
grep "encode" $WORKDIR/logs/encode_1.log | tail -20

# Calculate:
# FPS_achieved = output_frame_count / encoding_time_seconds
```

### 5. Disk Space Calculation
```bash
# Maximum disk usage:
# = MAX_PREFETCH * avg_input_size + MAX_PREFETCH * avg_output_size

# Example with 2GB average input, 500MB average output:
# = 10 * 2GB + 10 * 500MB = 20GB + 5GB = 25GB

# Recommendation: Allocate 1.5x this calculated space
# For example above: ~40GB
```

## Troubleshooting Performance

### GPU Utilization Low
1. Increase `ENCODE_JOBS` by 1 (up to 4-8)
2. Increase `MAX_PREFETCH` by 2-5
3. Check network speed (download bottleneck)
4. Check disk speed (I/O bottleneck)

### Too Much Disk Usage
1. Decrease `MAX_PREFETCH` by 50%
2. Accept slower GPU utilization (tradeoff)

### Encoding Stalls
1. Check network connectivity: `rclone about b2:`
2. Check disk space: `df -h /workspace/`
3. Check GPU health: `nvidia-smi`
4. Check logs for errors

### Out of Memory Errors
1. Decrease `ENCODE_JOBS` by 1
2. Close other applications
3. Check system RAM: `free -h`

## Benchmarking

Create a test set to benchmark your system:
```bash
# Add a few representative videos to a test bucket
# Then run with different configurations

# Balanced profile
source examples/config.prod.sh
time ./b2_vast_hevc_parallel.sh > /tmp/bench_balanced.log

# Fast profile
source examples/config.fast.sh
time ./b2_vast_hevc_parallel.sh > /tmp/bench_fast.log

# Compare results and choose best fit
```

## Multi-GPU Scaling

If you have multiple GPUs:

```bash
# Method 1: Multiple script instances (recommended)
# Machine 1
export ENCODE_JOBS=2
./b2_vast_hevc_parallel.sh &

# Machine 2
export ENCODE_JOBS=2
./b2_vast_hevc_parallel.sh &

# The claim file system prevents collisions automatically

# Method 2: Modify script for GPU affinity (advanced)
# Would require script modifications to target specific GPU
```

## Final Recommendations

1. **Start with Profile 2 (Balanced)** - good default for most users
2. **Run self-test** - validates your hardware
3. **Monitor first few files** - ensure GPU/network/disk working well
4. **Adjust based on actual measurements** - not theoretical
5. **Consider file sizes** - typical files will affect disk quota needed

For questions, check the main [README.md](../README.md) or [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
