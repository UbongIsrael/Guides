#!/bin/bash
set -e

echo ""
echo "========================================"
echo "  Ollama Server Setup Script"
echo "========================================"
echo ""

# --- Dependencies ---
echo "[1/4] Installing dependencies..."
sudo apt-get update -y -qq
sudo apt-get install -y curl screen zstd lshw
echo "      ✓ curl, screen, zstd, lshw installed"

# --- Ollama ---
echo ""
echo "[2/4] Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh
echo "      ✓ Ollama installed"

# --- Screen + serve ---
echo ""
echo "[3/4] Starting ollama serve in detached screen session 'ollama'..."
screen -dmS ollama bash -c 'ollama serve'
echo "      ✓ Screen session started"

# Wait for serve to be ready
echo "      Waiting for Ollama API to be ready..."
for i in {1..10}; do
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
ollama pull qwen3-coder-next:q4_K_M
echo "      ✓ Model ready"

echo ""
echo "========================================"
echo "  All done."
echo "  - Serve is running in screen 'ollama'"
echo "  - Reattach anytime: screen -r ollama"
echo "  - Detach again:     Ctrl+A, D"
echo "  - Test:             ollama run qwen3-coder-next:q4_K_M"
echo "========================================"