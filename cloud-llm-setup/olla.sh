#!/bin/bash
set -e

echo ""
echo "========================================"
echo "  Ollama Model Pull"
echo "========================================"
echo ""

echo "[1/2] Installing dependencies..."
sudo apt-get update -y -qq
sudo apt-get install -y zstd lshw
echo "      ✓ done"

echo ""
echo "[2/2] Pulling qwen3-coder-next:q4_K_M..."
echo "      (this will take a while)"
ollama pull qwen3-coder-next:q4_K_M
echo "      ✓ Model ready"

echo ""
echo "========================================"
echo "  Done. Ollama is already serving on"
echo "  http://0.0.0.0:11434"
echo "========================================"