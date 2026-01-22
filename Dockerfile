FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    git-lfs \
    wget \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Step 1: Clone Tencent's base repository (skip LFS files for now)
RUN GIT_LFS_SKIP_SMUDGE=1 git clone https://github.com/tencent-ailab/SongGeneration.git .

# Step 2: Download missing LFS file (Tencent repo hit LFS quota)
RUN wget -O /app/tools/new_prompt.pt \
    "https://github.com/tencent-ailab/SongGeneration/raw/refs/heads/main/tools/new_prompt.pt"

# Step 3: Clone BazedFrog Studio repo for custom files and patches
RUN git clone https://github.com/BazedFrog/SongGeneration-Studio.git /tmp/bazedfrog

# Step 4: Copy requirements files (tested, compatible versions)
RUN cp /tmp/bazedfrog/requirements.txt /app/requirements.txt && \
    cp /tmp/bazedfrog/requirements_nodeps.txt /app/requirements_nodeps.txt

# Step 5: Install huggingface-hub from PyPI
RUN pip3 install --no-cache-dir huggingface-hub

# Step 6: Install PyTorch for CUDA 12.1
RUN pip3 install --no-cache-dir torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 \
    --index-url https://download.pytorch.org/whl/cu121

# Step 7: Install application dependencies
RUN pip3 install --no-cache-dir -r requirements.txt && \
    pip3 install --no-cache-dir -r requirements_nodeps.txt --no-deps

# Step 8: Force numpy version for compatibility
RUN pip3 install --no-cache-dir numpy==1.26.4

# Step 9: Copy custom Python files from BazedFrog (main.py, generation.py, etc.)
RUN cp /tmp/bazedfrog/*.py /app/

# Step 10: Copy web assets
RUN mkdir -p /app/web/static && \
    cp -r /tmp/bazedfrog/web/static/* /app/web/static/

# Step 11: Apply patches for bug fixes (only files that exist at build time)
RUN cp /tmp/bazedfrog/patches/builders.py /app/codeclm/models/builders.py && \
    cp /tmp/bazedfrog/patches/gradio/levo_inference_lowmem.py /app/tools/gradio/levo_inference_lowmem.py

# Step 12: Save demucs patch for runtime application (after models download)
RUN mkdir -p /app/patches && \
    cp /tmp/bazedfrog/patches/demucs/apply.py /app/patches/demucs_apply.py

# Step 13: Cleanup
RUN rm -rf /tmp/bazedfrog

# Step 14: Create startup script that downloads models on first run
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Check if models are already downloaded\n\
if [ ! -d "/app/third_party/demucs" ]; then\n\
    echo "First startup detected - downloading models (~15GB, this will take 10-15 minutes)..."\n\
    python3 -c "from huggingface_hub import snapshot_download; \\\n\
        snapshot_download(repo_id=\"lglg666/SongGeneration-Runtime\", \\\n\
        local_dir=\"/app\", local_dir_use_symlinks=False)"\n\
    echo "Models downloaded successfully!"\n\
    \n\
    echo "Applying demucs patch..."\n\
    cp /app/patches/demucs_apply.py /app/third_party/demucs/models/apply.py\n\
    \n\
    echo "Setup complete!"\n\
else\n\
    echo "Models already downloaded, starting application..."\n\
fi\n\
\n\
# Start the application\n\
exec python3 main.py --host 0.0.0.0 --port 8000\n\
' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 8000

CMD ["/app/start.sh"]
