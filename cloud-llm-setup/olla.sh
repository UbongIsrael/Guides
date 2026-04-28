#!/bin/bash
set -e

echo ""
echo "========================================"
echo "  Ollama Model Pull (Ollama Image)"
echo "========================================"
echo ""

# --- Detect best storage location ---
echo "[0/3] Detecting storage..."
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
echo "[1/3] Installing dependencies..."
sudo apt-get update -y -qq
sudo apt-get install -y zstd lshw
echo "      ✓ done"

# --- Check Ollama is running ---
echo ""
echo "[2/3] Checking Ollama server..."
for i in {1..10}; do
  if curl -s http://localhost:11434 > /dev/null 2>&1; then
    echo "      ✓ Ollama is running"
    break
  fi
  if [ "$i" -eq 10 ]; then
    echo "      Ollama not detected. Starting manually..."
    export OLLAMA_KEEP_ALIVE=-1
    export OLLAMA_MAX_LOADED_MODELS=1
    ollama serve > /tmp/ollama.log 2>&1 &
    sleep 5
  fi
  sleep 2
done

# --- Pull model ---
echo ""
echo "[3/3] Pulling qwen3-coder-next:q4_K_M..."
echo "      (this will take a while)"
OLLAMA_MODELS=${OLLAMA_MODELS} ollama pull qwen3-coder-next:q4_K_M
echo "      ✓ Model ready"

echo ""
echo "========================================"
echo "  Done. Ollama is serving on"
echo "  http://0.0.0.0:11434"
echo "  Models stored at: ${OLLAMA_MODELS}"
echo "  - List models: OLLAMA_MODELS=${OLLAMA_MODELS} ollama list"
echo "  - Test:        OLLAMA_MODELS=${OLLAMA_MODELS} ollama run qwen3-coder-next:q4_K_M"
echo "========================================"