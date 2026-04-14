# Troubleshooting Guide

Common issues and solutions for `b2-hevc-parallel`.

## Installation Issues

### ffmpeg: hevc_nvenc not found

**Symptoms:**
```
Error: ffmpeg build does not expose hevc_nvenc
Script exited with code 3
```

**Causes:**
- FFmpeg not compiled with NVENC support
- Using system FFmpeg without NVENC

**Solutions:**
```bash
# Check if NVENC is available
ffmpeg -hide_banner -encoders 2>/dev/null | grep hevc_nvenc

# If not found, rebuild FFmpeg with NVENC
# See INSTALLATION.md → Option B: Build from source

# Verify successful build
ffmpeg -hide_banner -encoders | grep hevc_nvenc
# Should output a line like:
# hevc_nvenc            NVIDIA NVENC H.265/HEVC codec
```

### CUDA device init failed

**Symptoms:**
```
Error: ffmpeg sees hevc_nvenc, but CUDA device init failed
Script exited with code 4
```

**Causes:**
- NVIDIA drivers not installed
- GPU not detected
- CUDA not properly installed
- Incompatible GPU with NVENC

**Solutions:**

1. Check if GPU is detected:
```bash
lspci | grep -i nvidia
# Should show your GPU model

nvidia-smi
# Should show GPU information and memory
```

2. If no GPU found, install NVIDIA drivers:
```bash
# Ubuntu/Debian
sudo apt-get install nvidia-driver-535

# Or use driver manager
sudo ubuntu-drivers autoinstall

# Reboot
sudo reboot
```

3. Check CUDA runtime:
```bash
nvcc --version

# If not found, install CUDA toolkit
# See INSTALLATION.md → Step 2: CUDA Toolkit
```

4. Verify CUDA works:
```bash
ffmpeg -hide_banner -loglevel error -init_hw_device cuda=gpu:0 \
  -f lavfi -i nullsrc=s=16x16:r=1 -t 0.1 -f null - && echo "OK" || echo "FAILED"
```

5. Check if GPU is newer and supported:
```bash
# List NVIDIA GPU generations with NVENC:
# Maxwell (2014+): GTX 750+, GTX 960+, GTX 1080+, R9 Fury
# Pascal (2016+): GTX 1050+, RTX models, Titan X
# Volta (2017+): Titan V
# Turing (2018+): RTX 20 series
# Ampere (2020+): RTX 30 series
# Ada (2022+): RTX 40 series

nvidia-smi | head -5
```

### rclone: command not found

**Symptoms:**
```
Missing command: rclone
exit code 127
```

**Solutions:**
```bash
# Check if installed
which rclone

# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Or manually
sudo apt-get install rclone

# Verify
rclone version
```

## Self-Test Issues

### Self-test fails with "ENCODE FAILED"

**Check the detailed log:**
```bash
cat /workspace/hevc_job/logs/file_part2_subdir_test_mp4.log
```

**Common causes:**

1. **No available GPU memory:**
```bash
# Check free GPU memory
nvidia-smi

# Solution: Close other GPU applications
pkill -f cuda
```

2. **Unsupported pixel format:**
```
# Look for messages like "Unrecognized pixel format"
# Solution: Update FFmpeg or try with different input
```

3. **CUDA decode path failed message:**
```
# Normal if ALLOW_SW_DECODE_FALLBACK=1 (default)
# Script will retry with software decode
# If both fail, GPU may be incompatible
```

### Self-test fails: "Missing output"

**Symptoms:**
```
[ERROR] Self-test failed, missing output
```

**Causes:**
- FFmpeg encoding crashed
- Output directory doesn't exist
- Insufficient disk space

**Solutions:**
```bash
# Clean working directory
rm -rf /workspace/hevc_job

# Check disk space
df -h /workspace

# Run self-test with verbose logging
bash -x ./b2_vast_hevc_parallel.sh --self-test 2>&1 | tee selftest.log

# Check FFmpeg logs
tail -100 /workspace/hevc_job/logs/selftest_file.log
```

## B2 / Rclone Issues

### B2 authentication failed

**Symptoms:**
```
ERROR: command returned error code 1
# or in logs:
# Error: couldn't list directory
```

**Solutions:**

1. Verify B2 credentials:
```bash
# Re-run rclone configuration
rclone config

# Create new application key if needed:
# 1. Login to https://secure.backblaze.com/
# 2. Settings → Application Keys
# 3. Create new key with restricted bucket access
```

2. Test B2 access:
```bash
rclone lsf b2:
rclone lsf b2:your-bucket
rclone about b2:
```

3. Enable verbose logging:
```bash
rclone -vv lsf b2: > /tmp/rclone_test.log 2>&1
cat /tmp/rclone_test.log
```

4. Check rclone.conf:
```bash
cat ~/.config/rclone/rclone.conf | grep -A 5 "^\[b2\]"

# Should show:
# [b2]
# type = b2
# account_id = YOUR_ACCOUNT_ID
# app_key = YOUR_APPLICATION_KEY
```

### DOWNLOAD FAILED messages

**Symptoms:**
```
[TIMESTAMP] DOWNLOAD FAILED b2:bucket/path/file.mp4
```

**Check the download log:**
```bash
tail -50 /workspace/hevc_job/logs/download_part2_1.log
```

**Common causes:**

1. **Network timeout:**
```bash
# Increase timeout in script
# Or improve network connectivity

# For very slow networks, modify rclone flags in script:
# Change: RCLONE_FLAGS=(--stats=30s --stats-one-line --retries=5 --low-level-retries=20 --contimeout=60s --timeout=0)
# To: RCLONE_FLAGS=(--stats=30s --stats-one-line --retries=10 --low-level-retries=50 --contimeout=120s --timeout=0)
```

2. **B2 rate limit:**
```bash
# Check if many 429 errors in logs
grep "429" /workspace/hevc_job/logs/download_*.log

# Reduce parallelism
export DOWNLOAD_JOBS=2
```

3. **File doesn't exist:**
```bash
# Verify file exists on B2
rclone lsf b2:your-bucket/part2/path/ --include "filename"
```

### UPLOAD FAILED messages

**Symptoms:**
```
[TIMESTAMP] UPLOAD FAILED b2:bucket/path/file.hevc.mp4
```

**Solutions:**

1. Check upload log:
```bash
tail -50 /workspace/hevc_job/logs/encode_1.log | grep -A 5 "UPLOAD"
```

2. Verify output bucket has write permissions:
```bash
# Test upload
echo "test" > /tmp/test.txt
rclone copyto /tmp/test.txt b2:output-bucket/test.txt
rclone rm b2:output-bucket/test.txt
```

3. Check disk space (may run out during encoding):
```bash
df -h /workspace/hevc_job/
```

### VERIFY FAILED messages

**Symptoms:**
```
[TIMESTAMP] VERIFY FAILED b2:bucket/path/file.hevc.mp4
Upload succeeded but file not verified
```

**Causes:**
- File size mismatch (corruption or incomplete upload)
- File exists check failed

**Solutions:**

1. Check file sizes:
```bash
# Get local size
ls -lh /workspace/hevc_job/spool/file.hevc.mp4

# Get remote size
rclone lsf -R b2:output-bucket/path/file.hevc.mp4 --format "sp"

# Sizes should match
```

2. Wait a moment (B2 eventual consistency):
```bash
# Sometimes B2 hasn't indexed the file yet
# Check again in verification log
tail -20 /workspace/hevc_job/logs/file_*.log | grep -i verify
```

3. Try with exists-only verification (faster):
```bash
export VERIFY_MODE="exists"
./b2_vast_hevc_parallel.sh
```

## Encoding Issues

### ENCODE FAILED messages

**Symptoms:**
```
[TIMESTAMP] ENCODE FAILED /workspace/hevc_job/spool/file.input.mp4
```

**Check the per-file log:**
```bash
ls /workspace/hevc_job/logs/file_*.log | head -5

# View latest file log
tail -100 /workspace/hevc_job/logs/file_*.log
```

**Common causes:**

1. **Unsupported codec in source:**
```
# Look for: "Unknown encoder"
# Solution: Check if source is actually H.264/H.265/ProRes/etc
ffprobe /path/to/source/file.mp4 | grep "Video:"
```

2. **Insufficient GPU memory:**
```
# Look for: "out of memory" errors
# Solution:
export ENCODE_JOBS=1  # Reduce parallelism
```

3. **CUDA decode fallback failed:**
```
# Look for: "CUDA decode path failed" then "fallback: ... FAILED"
# This means even software decode failed

# Check with direct FFmpeg:
ffmpeg -i /path/to/file.mp4 -c:v hevc_nvenc -c:a copy -f null -

# May indicate corrupted source file
```

4. **Codec not supported:**
```
# Look for: "Codec or pixel format not supported"
# Some source codecs can't be decoded or encoded

# Solutions:
# - Try different source
# - Enable software decode fallback: ALLOW_SW_DECODE_FALLBACK=1
```

### Encoding hangs / stalls

**Symptoms:**
- Encoding appears to run but makes no progress
- GPU not being utilized
- Logs show encoding started but no completion

**Solutions:**

1. Monitor the encoding process:
```bash
# Check if FFmpeg is actually running
watch -n 1 'ps aux | grep ffmpeg'

# Monitor GPU activity
watch -n 1 'nvidia-smi'
```

2. If hung, kill and check logs:
```bash
pkill -9 ffmpeg

# Check what was being encoded
tail -100 /workspace/hevc_job/logs/encode_1.log

# Try encoding that file directly
ffmpeg -hwaccel cuda -hwaccel_output_format cuda -i /path/to/file.mp4 \
  -c:v hevc_nvenc -c:a copy /tmp/test_output.mp4
```

3. Potential issues:
```bash
# Out of disk space
df -h /workspace/hevc_job/

# Network connectivity lost (if reading from remote)
ping -c 1 8.8.8.8

# GPU driver crash
dmesg | tail -50 | grep -i nvidia

# Reboot if driver crashed
sudo reboot
```

## File Processing Issues

### Files being skipped (marked SKIP)

**Symptoms:**
```
[TIMESTAMP] SKIP remote exists
```

**Explanation:**
This is normal - files already in output bucket are skipped.

**To re-process:**
```bash
# Delete from output bucket first
rclone delete b2:output-bucket/path/

# Or manually delete specific files
rclone rm b2:output-bucket/part2/specific_file.mp4
```

### Same file processed twice

**Symptoms:**
- File listed in counters multiple times
- Two versions in output bucket

**Causes:**
- Script interrupted and restarted
- Claim file system race condition (rare)

**Solutions:**
```bash
# Clean state directory
rm -rf /workspace/hevc_job/state/claims/

# Then restart - files will be re-claimed but not duplicated

# To prevent, use strong file verification
export VERIFY_MODE="size"
```

## Performance Issues

### GPU utilization low (< 50%)

**Solutions:**
```bash
# Increase parallelism
export ENCODE_JOBS=4
export MAX_PREFETCH=12

# Check if bottleneck is elsewhere
tail -20 /workspace/hevc_job/logs/download_*.log | grep -i "error\|FAILED"

# Check network
speedtest-cli  # or ookla speedtest
```

### Disk space running out

**Solutions:**
```bash
# Reduce prefetch queue
export MAX_PREFETCH=4

# Or move to larger disk
export WORKDIR="/mnt/larger_disk/hevc_job"

# Delete successfully processed files more aggressively
# (Already default: DELETE_LOCAL_AFTER_UPLOAD=1)
```

### Very slow encoding

**Check:**
```bash
# Are you using p1 preset?
grep "NVENC_PRESET=" b2_vast_hevc_parallel.sh

# Use faster preset
export NVENC_PRESET="p5"
```

## Monitoring and Diagnostics

### Generate diagnostic report

```bash
#!/bin/bash
cat > /tmp/diagnostics.txt << 'EOL'
=== System Info ===
$(uname -a)

=== GPU ===
$(nvidia-smi)

=== FFMPEG ===
$(ffmpeg -version | head -3)
$(ffmpeg -hide_banner -encoders | grep hevc)

=== RCLONE ===
$(rclone version)
$(rclone about b2:)

=== Disk Space ===
$(df -h /workspace/)

=== Process Status ===
$(ps aux | grep -E "ffmpeg|rclone|parallel" | grep -v grep)

=== Recent Errors ===
$(tail -50 /workspace/hevc_job/logs/master.log | grep -i error)
EOL

cat /tmp/diagnostics.txt
```

### Check script health

```bash
# Count progress
for dir in /workspace/hevc_job/state/*.count; do
  echo "$(basename $dir): $(cat $dir)"
done

# Check active processes
pgrep -fa b2_vast_hevc_parallel.sh

# Monitor in real-time
watch -n 5 'echo "=== Counters ==="; for f in /workspace/hevc_job/state/*.count; do echo "$(basename $f): $(cat $f)"; done; echo ""; echo "=== Queued ==="; ls /workspace/hevc_job/spool/*.ready 2>/dev/null | wc -l'
```

## Getting Help

If you can't resolve the issue:

1. **Collect diagnostic info:**
```bash
# Save all logs
tar -czf /tmp/diagnostics_$(date +%s).tar.gz /workspace/hevc_job/logs/
```

2. **Run self-test:**
```bash
./b2_vast_hevc_parallel.sh --self-test 2>&1 | tee /tmp/selftest.log
```

3. **Check the main README:**
   - See [README.md](../README.md) for complete documentation

4. **Review related docs:**
   - [INSTALLATION.md](INSTALLATION.md) - setup issues
   - [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md) - optimization

## Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| hevc_nvenc not found | FFmpeg not built with NVENC | Rebuild FFmpeg with `--enable-nvenc` |
| CUDA device init failed | No GPU or drivers missing | Install NVIDIA drivers |
| rclone: command not found | rclone not installed | `curl https://rclone.org/install.sh \| sudo bash` |
| B2 authentication failed | Wrong credentials | Re-run `rclone config` |
| DOWNLOAD FAILED | Network/B2 issue | Check connectivity and quotas |
| ENCODE FAILED | Codec/GPU issue | Check logs, try direct ffmpeg |
| UPLOAD FAILED | Network/disk issue | Check disk space and connectivity |
| VERIFY FAILED | File corruption | Upload will retry automatically |
| Disk full | Insufficient space for prefetch | Reduce `MAX_PREFETCH` |
| GPU memory error | Insufficient VRAM | Reduce `ENCODE_JOBS` |
| Encoding hangs | Kernel/driver issue | Check `dmesg`, may need reboot |

For more help, refer to:
- FFmpeg documentation: https://ffmpeg.org/documentation.html
- Rclone B2 docs: https://rclone.org/b2/
- NVIDIA NVENC docs: https://docs.nvidia.com/video-technologies/video-codec-sdk/
