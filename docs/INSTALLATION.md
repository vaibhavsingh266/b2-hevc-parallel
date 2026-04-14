# Installation Guide

This guide walks you through setting up `b2-hevc-parallel` on your system.

## Prerequisites

### System Requirements
- **OS**: Linux (Bash 4.0+)
- **GPU**: NVIDIA GPU with NVENC support (Maxwell gen or newer)
- **Storage**: Sufficient local disk for temporary files during encoding
- **Network**: Good connectivity to Backblaze B2 (or stable internet connection)

### Required Software

#### 1. NVIDIA Drivers
```bash
# Check if GPU is recognized
nvidia-smi

# Install drivers (Ubuntu/Debian)
sudo apt-get install nvidia-driver-535  # or latest available
```

#### 2. CUDA Toolkit
```bash
# Install CUDA (Ubuntu 20.04 example)
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-ubuntu2004.pin
sudo mv cuda-ubuntu2004.pin /etc/apt/preferences.d/cuda-repository-pin-1605
sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/7fa2af80.pub
sudo add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/ /"
sudo apt-get update
sudo apt-get install cuda-toolkit-11-8

# Verify CUDA installation
nvcc --version
```

#### 3. FFmpeg with NVENC Support

**Option A: Install from official repositories (Ubuntu 22.04+)**
```bash
sudo apt-get update
sudo apt-get install ffmpeg
ffmpeg -hide_banner -encoders 2>/dev/null | grep hevc_nvenc
```

**Option B: Build from source (if pre-built doesn't have NVENC)**
```bash
# Install build dependencies
sudo apt-get install build-essential yasm pkg-config \
  libx264-dev libx265-dev libvpx-dev libopus-dev libvorbis-dev \
  libfdk-aac-dev libfreetype6-dev libass-dev libfontconfig1-dev

# Clone FFmpeg
git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
cd ffmpeg

# Configure with NVENC support
./configure \
  --enable-nonfree \
  --enable-cuda-nvcc \
  --enable-libnpp \
  --extra-cflags="-I/usr/local/cuda/include" \
  --extra-ldflags="-L/usr/local/cuda/lib64" \
  --enable-encoder=hevc_nvenc \
  --enable-encoder=h264_nvenc

# Build and install
make -j$(nproc)
sudo make install
sudo ldconfig

# Verify
ffmpeg -hide_banner -encoders | grep nvenc
```

#### 4. Rclone

```bash
# Install with official script
curl https://rclone.org/install.sh | sudo bash

# Or install from package repository (Ubuntu/Debian)
sudo apt-get install rclone

# Verify installation
rclone version
```

## Configuration

### 1. Configure Rclone for Backblaze B2

```bash
# Start interactive configuration
rclone config

# When prompted:
# - New remote name: b2
# - Provider: Backblaze B2
# - Account ID: [from B2 settings]
# - Application Key: [from B2 settings]
# - File permissions: Leave default
```

**Get B2 credentials:**
1. Login to [B2 Console](https://secure.backblaze.com/b2_buckets.htm)
2. Go to Account Settings → Application Keys
3. Create a new application key with restricted permissions to your buckets

**Test the configuration:**
```bash
# List B2 buckets
rclone lsf b2:

# List files in a bucket
rclone lsf b2:your-source-bucket

# Check connectivity
rclone about b2:
```

### 2. Edit Script Configuration

Edit `b2_vast_hevc_parallel.sh` and set your B2 details:

```bash
# Around line 7-12, set:
B2_REMOTE="b2"                    # Your rclone remote name
B2_SOURCE_BUCKET="source-bucket"  # Source bucket name
B2_OUTPUT_BUCKET="output-bucket"  # Destination bucket name
PARTS=(part2 part3 part4)         # Subdirectories to process
VIDEO_PATTERNS=("*.mp4" "*.mkv")  # Video file patterns
```

### 3. Create Working Directory

```bash
# Create working directory
mkdir -p /workspace/hevc_job

# Or use a different location by setting WORKDIR:
export WORKDIR="/mnt/fast_storage/hevc_job"
```

## Verify Installation

### Run Self-Test

```bash
./b2_vast_hevc_parallel.sh --self-test
```

Expected output (with NVIDIA GPU):
```
[2024-04-13T10:30:45Z] Preparing file lists...
[2024-04-13T10:30:47Z] NVENC is usable here, self-test will exercise NVENC
[2024-04-13T10:30:52Z] Self-test passed. Output: /workspace/hevc_job/tmp/selftest_remote/dest/part2/subdir/test.mp4 codec=hevc
```

Expected output (without NVIDIA GPU):
```
[2024-04-13T10:30:45Z] NVENC is not usable in this environment, self-test will validate the command shape with libx265 fallback
[2024-04-13T10:30:55Z] Self-test passed. Output: /workspace/hevc_job/tmp/selftest_remote/dest/part2/subdir/test.mp4 codec=hevc
```

### Check Individual Components

```bash
# Check FFmpeg with NVENC
ffmpeg -hide_banner -encoders 2>/dev/null | grep -i hevc_nvenc

# Check GPU CUDA support
ffmpeg -hide_banner -loglevel error -init_hw_device cuda=gpu:0 -f lavfi \
  -i nullsrc=s=16x16:r=1 -t 0.1 -f null - && echo "CUDA OK"

# Check FFprobe
ffprobe -version

# Check Rclone B2 connectivity
rclone lsf b2:
```

## Troubleshooting Installation

### "hevc_nvenc not found"
FFmpeg was not built with NVENC support. Rebuild FFmpeg with `--enable-nvenc` flag (see Option B above).

### "CUDA device init failed"
```bash
# Check NVIDIA drivers
nvidia-smi

# Reinstall drivers
sudo ubuntu-drivers autoinstall
sudo reboot

# Check CUDA installation
nvcc --version
```

### "rclone: command not found"
```bash
# Reinstall rclone
curl https://rclone.org/install.sh | sudo bash

# Or check if in PATH
which rclone
```

### "B2 authentication failed"
```bash
# Re-run rclone configuration
rclone config

# Test with verbose output
rclone -vv lsf b2:
```

## Make Script Executable

```bash
chmod +x b2_vast_hevc_parallel.sh

# Optionally place in PATH for easy access
sudo cp b2_vast_hevc_parallel.sh /usr/local/bin/
```

## Environment Setup (Optional)

Create a setup script to configure your environment:

```bash
#!/bin/bash
# setup_env.sh

export WORKDIR="/workspace/hevc_job"
export RCLONE_BIN="/usr/bin/rclone"
export FFMPEG_BIN="/usr/bin/ffmpeg"
export FFPROBE_BIN="/usr/bin/ffprobe"

# Source a configuration file
if [[ -f "examples/config.prod.sh" ]]; then
  source examples/config.prod.sh
fi

chmod +x b2_vast_hevc_parallel.sh
echo "Environment configured"
```

Usage:
```bash
source setup_env.sh
./b2_vast_hevc_parallel.sh
```

## Next Steps

1. Run the self-test: `./b2_vast_hevc_parallel.sh --self-test`
2. Review [README.md](../README.md) for detailed usage documentation
3. Check [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md) for optimization tips
4. Read [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues

## Support

For installation issues:
1. Check the component verification steps above
2. Review FFmpeg build logs if building from source
3. Check rclone configuration with verbose output (`rclone -vv`)
4. Consult NVIDIA driver documentation for GPU issues
