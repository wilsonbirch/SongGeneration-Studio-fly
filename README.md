# SongGeneration-Studio-fly

Fly.io deployment wrapper for [SongGeneration-Studio](https://github.com/BazedFrog/SongGeneration-Studio), a web interface for Tencent's LeVo AI song generation model.

## Overview

This deployment combines:
- **[Tencent's SongGeneration](https://github.com/tencent-ailab/SongGeneration)** - Core LeVo model implementation
- **[BazedFrog's SongGeneration-Studio](https://github.com/BazedFrog/SongGeneration-Studio)** - Custom UI, patches, and tested dependencies
- **Model weights** - Downloaded from [HuggingFace](https://huggingface.co/lglg666/SongGeneration-Runtime) (~15GB)

Generate complete songs with vocals, lyrics, and instrumentals from text prompts.

## Quick Start

```bash
# Deploy to Fly.io
fly deploy

# Monitor first startup (downloads models, takes 10-15 min)
fly logs

# Get your app URL
fly status
```

## Requirements

- Fly.io account with GPU access
- NVIDIA A10 GPU (24GB VRAM)
- 64GB RAM (configured in fly.toml)
- ~20GB storage for models

## Cost Warning

Running this app is expensive due to GPU requirements. Auto-scaling is enabled to minimize costs:
- Machines auto-stop when idle
- Machines auto-start on requests
- `min_machines_running = 0` configured

## Documentation

See [CLAUDE.md](CLAUDE.md) for detailed architecture, troubleshooting, and development guidance.

## License

MIT
