#!/bin/bash
set -e

echo ""
echo "========================================"
echo "  Ollama Server Setup Script (CUDA)"
echo "========================================"
echo ""

# --- Detect best storage location ---
echo "[0/4] Detecting storage..."
if [ -d "/workspace" ] && [ "$(df /workspace --output=avail | tail -1)" -gt "60000000" ]; then
  export OLLAMA_MODELS=/workspace/ollama/models
  mkdir -p /workspace/ollama/models
  echo "      ✓ Using /workspace for model storage ($(df -h /workspace --output=avail | tail -1 | tr -d ' ') free)"
else
  export OLLAMA_MODELS=/root/.ollama/models
  echo "      ✓ Using default /root/.ollama for model storage"
fi

# --- Dependencies ---
echo ""
echo "[1/4] Installing dependencies..."
sudo apt-get update -y -qq
sudo apt-get install -y curl screen zstd lshw
echo "      ✓ curl, screen, zstd, lshw installed"

# --- Ollama ---
echo ""
echo "[2/4] Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh
echo "      ✓ Ollama installed"

# --- Screen + serve (with env vars baked in) ---
echo ""
echo "[3/4] Starting ollama serve in detached screen session 'ollama'..."
screen -dmS ollama bash -c "
  export OLLAMA_MODELS=${OLLAMA_MODELS}
  export OLLAMA_KEEP_ALIVE=-1
  export OLLAMA_MAX_LOADED_MODELS=1
  ollama serve
"
echo "      ✓ Screen session started"

# Wait for serve to be ready
echo "      Waiting for Ollama API to be ready..."
for i in {1..15}; do
  if curl -s http://localhost:11434 > /dev/null 2>&1; then
    echo "      ✓ Ollama is live on :11434"
    break
  fi
  sleep 2
done

# --- Pull model ---
echo ""
echo "[4/4] Pulling qwen3-coder-next:q4_K_M..."
echo "      (this will take a while depending on your bandwidth)"
OLLAMA_MODELS=${OLLAMA_MODELS} ollama pull qwen3-coder-next:q4_K_M
echo "      ✓ Model ready"

echo ""
echo "========================================"
echo "  All done."
echo "  - Models stored at: ${OLLAMA_MODELS}"
echo "  - Serve is running in screen 'ollama'"
echo "  - Reattach anytime: screen -r ollama"
echo "  - Detach again:     Ctrl+A, D"
echo "  - List models:      OLLAMA_MODELS=${OLLAMA_MODELS} ollama list"
echo "  - Test:             OLLAMA_MODELS=${OLLAMA_MODELS} ollama run qwen3-coder-next:q4_K_M"
echo "========================================"