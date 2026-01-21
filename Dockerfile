FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone Tencent's base SongGeneration repo (contains codeclm and core models)
RUN git clone https://github.com/tencent-ailab/SongGeneration.git .

# Clone Studio wrapper to temporary location and overlay files
RUN git clone https://github.com/BazedFrog/SongGeneration-Studio.git /tmp/studio && \
    cp -r /tmp/studio/* . && \
    rm -rf /tmp/studio

# Install huggingface-hub to download third_party dependencies
RUN pip3 install --no-cache-dir huggingface-hub

# Download third_party directory from HuggingFace (contains demucs, Qwen2-7B, etc.)
# This is required for separator.py and levo_inference
RUN huggingface-cli download lglg666/SongGeneration-Runtime third_party --local-dir /app

# Fix Python path in model_server.py (upstream bug - tools/gradio doesn't exist, should be patches/gradio)
RUN sed -i 's|APP_DIR / "tools" / "gradio"|APP_DIR / "patches" / "gradio"|g' model_server.py

# Copy missing separator.py from Tencent repo to patches/gradio (required by levo_inference_lowmem.py)
RUN wget -O patches/gradio/separator.py \
    https://raw.githubusercontent.com/tencent-ailab/SongGeneration/main/tools/gradio/separator.py

# Install Python packages
RUN pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# Install application dependencies from requirements.txt
RUN pip3 install --no-cache-dir -r requirements.txt

# Pre-download models (optional but recommended to avoid timeout on first run)
# RUN python3 -c "from transformers import AutoModel; AutoModel.from_pretrained('facebook/musicgen-small')"

EXPOSE 8000

CMD ["python3", "main.py", "--host", "0.0.0.0", "--port", "8000"]
