# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Fly.io deployment wrapper** for [SongGeneration-Studio](https://github.com/BazedFrog/SongGeneration-Studio), a Gradio-based web application that generates complete songs (vocals, lyrics, instrumentals) using Tencent's LeVo AI model.

**Key Architecture Pattern**: This repository contains only deployment configuration (Dockerfile, fly.toml). The actual application code is cloned from the upstream repository at Docker build time.

## Technology Stack

- **Container**: Docker with NVIDIA CUDA 11.8 + cuDNN 8 on Ubuntu 22.04
- **Web Framework**: Gradio (Python 3.10)
- **ML Framework**: PyTorch with CUDA support, HuggingFace Transformers
- **Audio Processing**: FFmpeg, torchaudio
- **Cloud Platform**: Fly.io with GPU support (NVIDIA A10)
- **Infrastructure**: 32GB RAM, 8 performance CPUs, auto-scaling enabled

## Common Commands

### Deployment

```bash
# Deploy to Fly.io
fly deploy

# Check deployment status
fly status

# View logs
fly logs

# SSH into running machine
fly ssh console

# Scale machine manually
fly scale count 1

# Stop all machines (cost savings)
fly scale count 0
```

### Local Development

```bash
# Build Docker image locally
docker build -t songgen-studio .

# Run container locally (requires GPU)
docker run --gpus all -p 7860:7860 songgen-studio

# Run without GPU (will fail for inference but useful for testing container)
docker run -p 7860:7860 songgen-studio
```

### Testing Changes

```bash
# Test Dockerfile builds without full deployment
docker build --no-cache -t songgen-test .

# Validate fly.toml configuration
fly config validate
```

## Architecture Notes

### Build-Time vs Runtime

- **Build time**: Dockerfile clones the entire SongGeneration-Studio repository from GitHub
- **Runtime**: Container starts the Gradio app directly from cloned code at `/app`

This means:
- Changes to upstream repository require rebuilding the Docker image
- No git operations needed at runtime
- Large Docker images (~10-15GB with models and CUDA)

### Fly.io Configuration

The `fly.toml` file defines GPU-enabled VM configuration:
- `auto_stop_machines = true` and `min_machines_running = 0` enables serverless-style scaling
- `gpu_kind = "a10"` requests NVIDIA A10 GPU (24GB VRAM)
- `memory = '32gb'` is required for model loading and inference
- Primary region `ord` (Chicago) - can be changed based on user location/latency needs

### Port Configuration

- Gradio serves on port 7860 (standard)
- Environment variables `GRADIO_SERVER_NAME` and `GRADIO_SERVER_PORT` must match `internal_port` in fly.toml
- Fly.io handles HTTPS termination automatically

## Important Constraints

### GPU Requirements

The LeVo model requires significant VRAM:
- Minimum: 10GB VRAM
- Recommended: 24GB VRAM (A10 provides this)
- Without GPU, the application will fail at model loading

### Cost Considerations

Running this application is expensive:
- NVIDIA A10 GPU instances are high-cost on Fly.io
- Auto-scaling to 0 machines is critical for cost control
- Consider setting `auto_stop_machines = true` to stop machines after inactivity

### Upstream Dependency

This repository has a hard dependency on the upstream SongGeneration-Studio repository:
- Breaking changes upstream will break deployments
- The Dockerfile clones from `main` branch (no version pinning)
- Consider pinning to specific commit SHA for stability:
  ```dockerfile
  RUN git clone https://github.com/BazedFrog/SongGeneration-Studio.git . && \
      git checkout <commit-sha>
  ```

## Modifying the Deployment

### Changing Regions

Edit `fly.toml`:
```toml
primary_region = "ord"  # Chicago
# Other options: yyz (Toronto), lax (Los Angeles), iad (Virginia), etc.
```

Verify GPU availability in region: `fly platform regions`

### Updating Python Dependencies

Dependencies are installed in the Dockerfile. To modify:
1. Edit the `RUN pip3 install` commands in Dockerfile
2. Rebuild and redeploy

### Pre-downloading Models

Uncomment the model download step in Dockerfile to avoid timeouts on first run:
```dockerfile
RUN python3 -c "from transformers import AutoModel; AutoModel.from_pretrained('facebook/musicgen-small')"
```

This increases build time but improves first-run experience.

## File Structure

```
SongGeneration-Studio-fly/     # This repository (deployment wrapper)
├── Dockerfile                  # Container build configuration
├── fly.toml                    # Fly.io deployment manifest
├── README.md                   # Project description
├── LICENSE                     # MIT License
├── .gitignore                  # Git ignore rules
└── .env                        # Environment variables (empty)

/app (in container)             # Cloned at build time from upstream
├── app.py                      # Gradio application entry point
├── generation.py               # Song generation logic
├── model_server.py             # LeVo model inference
└── [other upstream files]
```

## Troubleshooting

### Build Failures
- Check upstream repository is accessible: `curl -I https://github.com/BazedFrog/SongGeneration-Studio`
- Verify CUDA compatibility if changing base image versions
- Ensure ffmpeg installs correctly (required for audio processing)

### Runtime Failures
- Check GPU allocation: `fly ssh console -C "nvidia-smi"`
- Verify model downloads: Most failures are due to HuggingFace model download timeouts
- Check memory usage: 32GB should be sufficient, but complex generations may need more

### Deployment Failures
- Verify GPU region availability: Not all Fly.io regions support A10 GPUs
- Check Fly.io credits/billing: GPU machines require active payment
- Validate fly.toml: `fly config validate`
