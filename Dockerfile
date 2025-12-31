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

# Clone the repo
RUN git clone https://github.com/BazedFrog/SongGeneration-Studio.git .

# Install Python packages
RUN pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
RUN pip3 install --no-cache-dir gradio transformers accelerate

# Pre-download models (optional but recommended to avoid timeout on first run)
# RUN python3 -c "from transformers import AutoModel; AutoModel.from_pretrained('facebook/musicgen-small')"

EXPOSE 7860

# Make start script executable if it exists
RUN chmod +x start.sh || true

CMD ["python3", "app.py", "--server-name", "0.0.0.0", "--server-port", "7860"]
