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

# Install application dependencies from requirements.txt
RUN pip3 install --no-cache-dir -r requirements.txt

# Pre-download models (optional but recommended to avoid timeout on first run)
# RUN python3 -c "from transformers import AutoModel; AutoModel.from_pretrained('facebook/musicgen-small')"

EXPOSE 8000

CMD ["python3", "main.py", "--host", "0.0.0.0", "--port", "8000"]
