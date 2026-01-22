# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Fly.io deployment wrapper** for [SongGeneration-Studio](https://github.com/BazedFrog/SongGeneration-Studio), a FastAPI-based web application that generates complete songs (vocals, lyrics, instrumentals) using Tencent's LeVo AI model.

**Key Architecture Pattern**: This deployment replicates the Pinokio installation process:
1. Clones Tencent's base [SongGeneration repository](https://github.com/tencent-ailab/SongGeneration) (contains core model code)
2. Downloads ~15GB of models from HuggingFace ([lglg666/SongGeneration-Runtime](https://huggingface.co/lglg666/SongGeneration-Runtime)) at runtime
3. Overlays BazedFrog's custom files (UI, patches, tested dependencies) on top
4. Applies bug fix patches for Windows compatibility, audio quality, and memory optimization

## Technology Stack

- **Container**: Docker with NVIDIA CUDA 12.1 + cuDNN 8 on Ubuntu 22.04
- **Web Framework**: FastAPI + React (custom UI, not Gradio)
- **ML Framework**: PyTorch 2.5.1 (pinned for compatibility), HuggingFace Transformers
- **Audio Processing**: FFmpeg, torchaudio, Demucs (vocal separation)
- **Cloud Platform**: Fly.io with GPU support (NVIDIA A10)
- **Infrastructure**: A10 VM (24GB VRAM, 64GB RAM required), auto-scaling enabled

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
docker run --gpus all -p 8000:8000 songgen-studio

# Run without GPU (will fail for inference but useful for testing container)
docker run -p 8000:8000 songgen-studio
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

- **Build time**:
  - Clones Tencent's base SongGeneration repository
  - Downloads missing LFS file (`new_prompt.pt`)
  - Clones BazedFrog Studio for custom files and patches
  - Installs PyTorch 2.5.1 and dependencies
  - Copies custom Python files, web assets, and applies patches
  - Image size: ~5-8GB

- **Runtime** (first startup only):
  - Downloads ~15GB of models from HuggingFace to `/app`
  - Applies demucs patch after models are downloaded
  - Creates marker file to skip downloads on subsequent startups
  - First startup: 10-15 minutes
  - Subsequent startups: <1 minute

This means:
- Models download once per machine (not preserved if machine is destroyed)
- Build deployments are faster (~5-10 min) vs including models in image (~20-30 min)
- Changes to upstream repositories require rebuilding the Docker image

### Fly.io Configuration

The `fly.toml` file defines GPU-enabled VM configuration:
- `size = "a10"` requests NVIDIA A10 GPU (24GB VRAM)
- `memory = "64gb"` allocates 64GB of CPU RAM (required - 32GB default causes OOM)
- `auto_stop_machines = true` and `min_machines_running = 0` enables serverless-style scaling
- `primary_region = "ord"` (Chicago) - can be changed based on user location/latency needs

### Port Configuration

- Application serves on port 8000
- `internal_port = 8000` in fly.toml must match the port in Dockerfile CMD
- Fly.io handles HTTPS termination automatically

## Important Constraints

### GPU Requirements

The LeVo model requires significant VRAM:
- Minimum: 10GB VRAM
- Model usage: ~22GB VRAM
- Recommended: 24GB VRAM (A10 provides this)
- Without GPU, the application will fail at model loading

### RAM Requirements

The application requires significant CPU RAM in addition to GPU VRAM:
- Minimum: 64GB RAM (32GB is insufficient and causes OOM kills)
- The model uses ~22GB of VRAM but also requires ~31GB+ of CPU RAM for:
  - Model loading and preprocessing
  - Audio processing and separation
  - Python runtime overhead
  - Web server and API
- Set `memory = "64gb"` in fly.toml to avoid out-of-memory errors

### Cost Considerations

Running this application is expensive:
- NVIDIA A10 GPU instances are high-cost on Fly.io
- Auto-scaling to 0 machines is critical for cost control
- Consider setting `auto_stop_machines = true` to stop machines after inactivity

### Upstream Dependencies

This repository has dependencies on multiple upstream repositories:

1. **Tencent SongGeneration** (base model code):
   - Repository: https://github.com/tencent-ailab/SongGeneration
   - Clones from `main` branch (no version pinning)
   - Contains `codeclm/` directory with core model implementation

2. **BazedFrog SongGeneration-Studio** (UI and patches):
   - Repository: https://github.com/BazedFrog/SongGeneration-Studio
   - Provides tested requirements.txt with compatible versions
   - Includes custom FastAPI backend and React UI
   - Contains bug fix patches for builders.py, demucs/apply.py, levo_inference_lowmem.py

3. **HuggingFace Model Repository** (model weights):
   - Repository: https://huggingface.co/lglg666/SongGeneration-Runtime
   - Size: ~15GB
   - Downloaded at runtime, not build time
   - Contains ckpt/, third_party/demucs, third_party/Qwen2-7B

Breaking changes in any of these will break deployments. Consider pinning to specific commits for production stability.

### Known Issues

**"Full Song" Button Behavior**:
- The "Full Song" output mode requires lyrics to be present in at least one song section
- If no lyrics exist, the app automatically switches from "Full Song" to "Instrumental"
- This makes the button appear unclickable - **add lyrics first** to enable "Full Song" mode
- See `/web/static/app.js` for the auto-override logic

## Modifying the Deployment

### Changing Regions

Edit `fly.toml`:
```toml
primary_region = "ord"  # Chicago
# Other options: yyz (Toronto), lax (Los Angeles), iad (Virginia), etc.
```

Verify GPU availability in region: `fly platform regions`

### Updating Python Dependencies

Dependencies come from BazedFrog's tested requirements files:
1. Clone BazedFrog repo locally to see current requirements
2. To modify: Edit the pip install commands in Dockerfile
3. **Important**: PyTorch must stay pinned to 2.5.1 for compatibility
4. Rebuild and redeploy

### Changing Model Download Strategy

Current approach: Download models at runtime (first startup)
- Pros: Faster builds (~5-10 min), smaller images (~5-8GB)
- Cons: 10-15 min first startup, models lost if machine destroyed

Alternative: Include models in Docker image
- Pros: Instant startup
- Cons: Very slow builds (20-30 min), huge images (20-30GB), deployment timeouts
- To implement: Move HuggingFace download from start.sh to Dockerfile RUN step

### Adding Persistent Volume Storage

To preserve models across machine restarts:
```bash
# Create volume in same region
fly volumes create songgen_models --size 20 --region ord
```

Add to fly.toml:
```toml
[[mounts]]
  source = "songgen_models"
  destination = "/data"
```

Update start.sh to check `/data/.models_downloaded` instead of `/app/third_party/demucs`

## File Structure

```
SongGeneration-Studio-fly/     # This repository (deployment wrapper)
├── Dockerfile                  # Container build configuration
├── fly.toml                    # Fly.io deployment manifest (includes memory = "64gb")
├── CLAUDE.md                   # This file - guidance for Claude Code
├── README.md                   # Project description
├── LICENSE                     # MIT License
└── .gitignore                  # Git ignore rules

/app (in container)             # Built from multiple sources
├── # From Tencent SongGeneration:
├── codeclm/                    # Core model implementation
│   ├── models/                 # Model definitions (builders.py patched by BazedFrog)
│   ├── trainer/                # Training code
│   ├── tokenizer/              # Audio tokenization
│   └── utils/                  # Utilities
├── tools/                      # Original Gradio tools
│   ├── new_prompt.pt           # Downloaded separately (LFS quota issue)
│   └── gradio/
│       ├── levo_inference_lowmem.py  # Patched by BazedFrog
│       └── separator.py        # Downloaded from Tencent repo
├── conf/                       # Configuration files
│
├── # Downloaded from HuggingFace at runtime:
├── ckpt/                       # Model checkpoints (~15GB)
│   ├── encode-s12k.pt
│   ├── model_1rvq/
│   ├── model_septoken/
│   └── vae/
├── third_party/                # Third-party models
│   ├── demucs/                 # Vocal separation (apply.py patched by BazedFrog)
│   │   ├── ckpt/htdemucs.pth
│   │   └── models/
│   ├── Qwen2-7B/               # Language model
│   └── stable_audio_tools/
│
├── # From BazedFrog SongGeneration-Studio:
├── main.py                     # FastAPI application entry point
├── generation.py               # Generation logic
├── model_server.py             # Model serving
├── requirements.txt            # Tested, compatible dependencies
├── requirements_nodeps.txt     # No-deps installations
├── web/                        # React frontend
│   └── static/
│       ├── index.html
│       ├── app.js              # Main React app
│       ├── components.js
│       └── styles.css
├── patches/                    # Patches to apply at runtime
│   └── demucs_apply.py         # Applied after models download
└── start.sh                    # Startup script (downloads models on first run)
```

## Troubleshooting

### Build Failures

**ModuleNotFoundError: No module named 'separator'**:
- The `separator.py` file is downloaded from Tencent repo at build time
- Located at `/app/patches/gradio/separator.py` after overlaying BazedFrog files
- If missing, check that wget step in Dockerfile succeeded

**ModuleNotFoundError: No module named 'third_party'**:
- The `third_party/` directory is downloaded from HuggingFace at runtime, not build time
- Check startup logs with `fly logs` to see if download completed
- Models download on first startup only (~15GB, takes 10-15 minutes)

**PyTorch version conflicts**:
- Must use PyTorch 2.5.1 (pinned in Dockerfile)
- PyTorch 2.6+ changed `weights_only=True` default which breaks model loading
- CUDA 12.1 is required for A10 GPU compatibility

**Image export timeout during deployment**:
- Occurs when including 15GB of models in Docker image (~20-30GB total)
- Solution: Download models at runtime instead (current approach)
- Alternative: Use `fly deploy --local-only` to build locally if you have Docker

### Runtime Failures

**Out of Memory (OOM) Killed**:
- Symptom: `Out of memory: Killed process` in logs, process using ~31GB RAM
- Cause: A10 default RAM (32GB) is insufficient
- **Solution**: Add `memory = "64gb"` to `[[vm]]` section in fly.toml and redeploy
- The LeVo model needs ~22GB VRAM + ~31GB+ CPU RAM

**Generation failed: invalid load key, 'v'**:
- Indicates corrupted or incomplete model download
- Check if models fully downloaded: `fly ssh console` then `ls -lh /app/ckpt/`
- If incomplete, delete and retry: Models re-download if `/app/third_party/demucs` doesn't exist

**Model server fails to start**:
- Check GPU allocation: `fly ssh console -C "nvidia-smi"`
- Verify CUDA version matches: Should show CUDA 12.1
- Check model download logs during first startup

**"Full Song" button not working**:
- This is expected behavior if no lyrics are present
- Add lyrics to at least one song section to enable "Full Song" mode
- "Instrumental" mode is automatically selected when no lyrics exist

### Deployment Failures

**Insufficient resources to create new machine with existing volume**:
- Occurs when volume region/size doesn't match VM requirements
- Delete old volume: `fly volumes delete <volume-id>`
- Current setup doesn't use volumes (models download to ephemeral storage)
- To add persistent volumes: Create volume in same region as primary_region

**GPU not available in region**:
- Not all Fly.io regions support A10 GPUs
- Check availability: `fly platform regions`
- Change `primary_region` in fly.toml if needed

**Build timeout or network errors**:
- HuggingFace downloads can be large and slow
- First startup takes 10-15 minutes - this is expected
- Check logs with `fly logs` to monitor progress
