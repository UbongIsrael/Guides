# Cloud LLM Setup Guide
### By Sheikh — Self-Hosted Agentic Coding with Open-Weight Models

> A practical, public-facing guide for developers who want to run powerful open-weight LLMs on cloud GPUs, tunnel them to their local machine, and use them as a coding agent via [OpenCode](https://opencode.ai). Built from real deployment experience — including every error along the way.

---

## Table of Contents

1. [Overview](#1-overview)
2. [How to Evaluate Any GPU](#2-how-to-evaluate-any-gpu)
   - [The Metrics That Actually Matter](#the-metrics-that-actually-matter)
   - [Single GPU vs Multi-GPU](#single-gpu-vs-multi-gpu)
   - [How Model Size Affects Hardware Requirements](#how-model-size-affects-hardware-requirements)
   - [Recommended GPU Tiers](#recommended-gpu-tiers)
3. [Model Recommendations](#3-model-recommendations)
4. [Setup Paths](#4-setup-paths)
   - [Which Path Should You Use?](#which-path-should-you-use)
   - [Path A — CUDA Image (setup.sh)](#path-a--cuda-image-setupsh)
   - [Path B — Ollama Image (olla.sh)](#path-b--ollama-image-ollash)
5. [Post-Setup: Storage Fix](#5-post-setup-storage-fix)
6. [Tunnel to Your Local Machine](#6-tunnel-to-your-local-machine)
7. [Configure OpenCode](#7-configure-opencode)
8. [Assistive & Troubleshooting Commands](#8-assistive--troubleshooting-commands)
9. [Do's and Don'ts](#9-dos-and-donts)
10. [Contact](#10-contact)

---

## 1. Overview

This guide walks through setting up an open-weight LLM on a cloud GPU — rented pay-as-you-go — and exposing it to your local machine so tools like OpenCode can use it as a coding agent. The whole stack is:

```
Cloud GPU (Ollama serving the model)
        ↓  SSH tunnel
Local machine (port 11434)
        ↓
OpenCode → talks to the model like any other provider
```

No subscriptions, no per-token API costs after setup. You pay only for the hours your GPU is running.

**Target model used in this guide:** `qwen3-coder-next:q4_K_M` (~51GB, 80B MoE)
**Target hardware:** Single GPU with 48GB+ VRAM
**Tested provider:** [Vast.ai](https://vast.ai)

---

## 2. How to Evaluate Any GPU

Before renting any GPU for LLM inference, you need to understand what actually makes a GPU fast for this workload. The spec sheet numbers that matter for gaming or rendering are often **not** the ones that matter for LLMs.

---

### The Metrics That Actually Matter

#### 1. VRAM Capacity (Most Important)
VRAM is the hard ceiling. The entire model — or as much of it as possible — must fit in VRAM. If the model overflows, layers spill to system RAM and get swapped over the PCIe bus, dropping generation speed from ~20 tok/s to ~2–5 tok/s. **This single factor will make or break your setup.**

Rule of thumb for quantized models:

| Quantization | VRAM needed (per billion params) |
|---|---|
| FP16 / BF16 | ~2GB per B |
| INT8 / Q8 | ~1GB per B |
| Q4_K_M | ~0.5GB per B |
| Q2_K | ~0.25GB per B |

A 80B model at Q4_K_M needs approximately **46–51GB VRAM** — which is why 48GB GPUs are the sweet spot for this class.

#### 2. Memory Bandwidth (Second Most Important)
LLM token generation (the part you feel — each new token appearing) is almost entirely **memory-bandwidth bound**. Every token requires loading billions of weight values from VRAM into compute units. The faster this transfer, the faster your tok/s.

This is measured in **GB/s**. Higher is better. Compare:

| GPU | Memory Bandwidth |
|---|---|
| RTX 5880 Ada | 960 GB/s |
| RTX 6000 Ada | 960 GB/s |
| RTX 4090 | 1,008 GB/s |
| H100 SXM | 3,350 GB/s |
| A100 SXM | 2,000 GB/s |

A consumer GPU with high bandwidth (RTX 4090 at 1,008 GB/s) can outperform a server GPU with lower bandwidth for pure generation speed at this model size.

#### 3. TFLOPS (Least Important for Generation)
TFLOPS measures raw compute throughput. It matters for **prompt processing** (reading your input context) but is almost irrelevant for **token generation** (which is what feels slow). Providers like Vast.ai prominently display TFLOPS in listings — treat it as a secondary metric, not the headline.

A GPU with 120 TFLOPS but fragmented across 4 cards over PCIe will generate tokens **slower** than a single GPU with 91 TFLOPS and unified VRAM.

#### 4. Memory Bus Width
Closely tied to bandwidth — the wider the bus, the more data can flow simultaneously. 384-bit bus (RTX 6000 Ada) handles memory more efficiently than a 192-bit bus (RTX 4070). Look for this when bandwidth numbers aren't listed.

#### 5. ECC Memory
Error-Correcting Code memory detects and auto-corrects single-bit memory errors in hardware. Consumer GPUs (GeForce line) do not have ECC. Professional/workstation GPUs (Quadro, RTX Ada series with full SKU number) do. For long agentic sessions where the model runs for 30–60 minutes on large codebases, ECC prevents subtle weight corruption that causes garbled or inconsistent outputs. Not a dealbreaker for short sessions, but important for sustained work.

#### 6. Driver Class: Consumer vs Professional
Consumer GeForce drivers are not certified for sustained compute workloads. They can thermal throttle aggressively, have less stable long-session behavior, and lack enterprise management features. Professional cards (RTX 6000 Ada, RTX 5880 Ada, A-series) use Quadro/NVIDIA Studio drivers — designed for 24/7 compute. Providers like Vast.ai host both; look for the full professional card name, not just "RTX XXXX".

---

### Single GPU vs Multi-GPU

This is one of the most misunderstood decisions when renting cloud GPUs. A multi-GPU listing with more total VRAM and higher combined TFLOPS can actually perform **worse** than a single GPU for LLM inference. Here's why:

#### When Multi-GPU Helps
Multi-GPU setups improve inference only when GPUs are connected via **NVLink** (NVIDIA's high-speed GPU-to-GPU interconnect). NVLink allows GPUs to share a unified memory pool and communicate at very high bandwidth:

| Interconnect | Bandwidth | Memory pooling |
|---|---|---|
| PCIe 4.0 x16 | ~32 GB/s | ❌ No |
| NVLink (3090) | ~112 GB/s | ✅ Yes (24+24=48GB) |
| NVLink (H100) | 900 GB/s | ✅ Yes |

With NVLink, two RTX 3090s (24GB each) can pool into a single 48GB address space, behaving like one GPU for the model. Without NVLink, tensor parallelism over PCIe introduces synchronization overhead on every attention layer — typically reducing effective throughput by 35–55%.

**The rule:** Multi-GPU only makes sense if NVLink is present and confirmed. Otherwise, always prefer a single GPU with more VRAM.

#### Consumer Cards and NVLink
Most modern consumer cards have dropped NVLink support. Only a few exceptions:
- RTX 3090 / 3090 Ti — supports NVLink (2-way only)
- RTX 2080 Ti — supports NVLink
- RTX 4090 and newer GeForce — **no NVLink**

All professional/datacenter cards (A100, H100, H200) support NVLink.

#### PCIe Multi-GPU — The Real Cost
If you see a listing like "4× RTX 4070 (12GB each) — 48GB total, 117 TFLOPS", this looks attractive. In practice:

- Each GPU holds ~12GB of model weights — zero KV cache headroom
- Every forward pass synchronizes across 4 GPUs over PCIe (~32 GB/s)
- All-reduce operations on every layer add latency
- Long context requests (large codebases) cause KV cache OOM mid-session

**Do not be deceived by aggregate TFLOPS or total VRAM in PCIe multi-GPU setups.**

---

### How Model Size Affects Hardware Requirements

LLMs come in a range of sizes. Understanding which parameters are *active* during inference (relevant for MoE models) vs total is critical for hardware selection.

#### Dense Models (All parameters active per token)
Every parameter participates in every token generated. VRAM requirement scales linearly with model size.

| Model size | Q4_K_M VRAM | Minimum GPU |
|---|---|---|
| 7B–8B | ~5–6GB | RTX 3060 12GB |
| 13B–14B | ~8–10GB | RTX 3080 10GB |
| 32B–34B | ~20–22GB | RTX 3090 24GB |
| 70B | ~42–44GB | 2× RTX 3090 NVLink or RTX 6000 Ada |
| 72B | ~44–46GB | RTX 6000 Ada / RTX 5880 Ada |

#### MoE Models (Mixture of Experts — only a subset of params active)
MoE models have a large total parameter count but only activate a fraction per token. This is what makes models like MiniMax M2.5 (229B total, 10B active) or Qwen3-Coder-Next (80B total, ~3B active per token) efficient to run.

For MoE models, what matters is:
1. **Total parameters** — determines VRAM needed to store the model
2. **Active parameters per token** — determines compute speed per token

A 229B MoE model with 10B active params feels like running a 10B model from a 229B library — inference is fast once the model is loaded, but the full 229B still needs to fit in VRAM.

| Model | Total params | Active params | Q4 VRAM | Practical setup |
|---|---|---|---|---|
| Qwen3-Coder-Next 80B | 80B | ~3B | ~46–51GB | 1× 48GB GPU |
| Qwen3.5 397B | 397B | 17B | ~280GB | 4× A100 80GB |
| MiniMax M2.5 229B | 229B | 10B | ~160GB | 2× H100 80GB |
| Kimi K2.5 1T | 1T | 32B | ~375GB (Q2) | 8× H100+ |

---

### Recommended GPU Tiers

Based on model size and budget, here are concrete GPU recommendations for self-hosted inference:

#### Tier 1 — Small Models (7B–14B), Budget
**Target:** Quick local assistant, fast inference, low cost  
**Best GPUs:** RTX 3080 10GB, RTX 3060 12GB, RTX 4070 12GB  
**Expected cost on Vast.ai:** ~$0.10–0.20/hr  
**tok/s:** 40–80+  
**Good for:** Qwen3-Coder 8B, DeepSeek-Coder 7B, Mistral 7B  

#### Tier 2 — Mid Models (30B–34B), Balanced
**Target:** Solid coding assistant, fits in 24GB  
**Best GPUs:** RTX 3090 24GB, RTX 4090 24GB (if verified), RTX A5000 24GB  
**Expected cost on Vast.ai:** ~$0.25–0.50/hr  
**tok/s:** 20–40  
**Good for:** Qwen3-Coder 30B, Qwen3.5 27B, DeepSeek-Coder-V2 Lite  

#### Tier 3 — Large Models (70B–80B), ✅ This Guide's Target
**Target:** Near-frontier open-weight coding performance  
**Best GPUs:** RTX 6000 Ada 48GB ⭐, RTX 5880 Ada 48GB ⭐, RTX A6000 48GB  
**Expected cost on Vast.ai:** ~$0.25–0.45/hr  
**tok/s:** 15–25  
**Good for:** Qwen3-Coder-Next 80B, LLaMA 3.3 70B, Qwen3.5 72B  
**Why these win:** Single GPU, 48GB unified VRAM, professional drivers, ECC memory, no inter-GPU overhead  

#### Tier 4 — Very Large MoE (200B+), High Budget
**Target:** Claude Opus-class open-weight performance  
**Best GPUs:** 2× H100 SXM 80GB (NVLink), 4× A100 SXM 80GB (NVLink)  
**Expected cost:** ~$3.50–5.50/hr  
**tok/s:** 30–80 (MoE efficiency)  
**Good for:** MiniMax M2.5, Qwen3.5 397B, GLM-5  

> **Provider note:** Vast.ai is the most affordable pay-as-you-go option for Tier 2 and 3. RunPod offers more consistent uptime for Tier 4. Always verify the GPU model with `nvidia-smi` after SSHing in — listing descriptions can be inaccurate.

---

## 3. Model Recommendations

| Model | Size | VRAM (Q4) | SWE-bench | Best for |
|---|---|---|---|---|
| **Qwen3-Coder-Next 80B** ⭐ | 80B MoE | ~51GB | 70.6% | Best single-48GB-GPU coding model |
| **Qwen3.5 27B** | 27B dense | ~18GB | ~73% | Best mid-tier, fits single 24GB GPU |
| **MiniMax M2.5** | 229B MoE | ~160GB | 80.2% | Closest open-weight to Claude Opus |
| **GLM-5** | 744B MoE | ~595GB | 77.8% | Strong SWE-bench, heavy hardware |
| **DeepSeek V3.2** | 685B MoE | cluster | 73% | Best value via API fallback |

For the hardware covered in this guide (single 48GB GPU), **Qwen3-Coder-Next 80B at Q4_K_M** is the recommended model. It is the most capable model that fits cleanly in one GPU at this VRAM tier.

---

## 4. Setup Paths

There are two ways to set up your cloud node depending on which base image your provider offers. Both paths end at the same place: Ollama serving a model on port 11434.

---

### Which Path Should You Use?

| Situation | Use |
|---|---|
| Provider offers a **CUDA / Ubuntu** base image | [Path A — setup.sh](#path-a--cuda-image-setupsh) |
| Provider offers a dedicated **Ollama** image | [Path B — olla.sh](#path-b--ollama-image-ollash) |
| Not sure | Check if `ollama` command exists on SSH: if yes, use Path B |

---

### Path A — CUDA Image (setup.sh)

Use this when you're starting from a bare CUDA/Ubuntu image. The script installs all dependencies, Ollama itself, starts the server in a detached screen session, and pulls the model.

📄 **Script:** [`setup.sh`](https://github.com/UbongIsrael/Guides/blob/main/cloud-llm-setup/setup.sh)

#### What the script does:
1. Installs `curl`, `screen`, `zstd`, `lshw` via apt
2. Installs Ollama via the official install script
3. Starts `ollama serve` inside a detached `screen` session named `ollama`
4. Waits for the API to be ready on port 11434
5. Pulls `qwen3-coder-next:q4_K_M`

#### Step-by-step commands:

**Step 1 — SSH into your node**
```bash
ssh -p <PORT> root@<IP>
```

**Step 2 — Verify the GPU before anything else**
```bash
nvidia-smi
```
Confirm the GPU name and VRAM match what you rented. If they don't match — disconnect and pick a different instance.

**Step 3 — Check available disk space**
```bash
df -h /
```
You need at least **80GB free** on the root filesystem. If it shows less, see [Section 5 — Storage Fix](#5-post-setup-storage-fix) before proceeding.

**Step 4 — Pull and run the script**
```bash
curl -fsSL https://raw.githubusercontent.com/UbongIsrael/Guides/main/cloud-llm-setup/setup.sh -o setup.sh
chmod +x setup.sh && ./setup.sh
```

The model pull is ~51GB. Leave the terminal open. You'll see a progress bar. The script prints `✓ Model ready` when complete.

**Step 5 — Verify Ollama is running**
```bash
curl http://localhost:11434
# Expected: Ollama is running
```

**Step 6 — Pre-load the model into VRAM**
```bash
ollama run qwen3-coder-next:q4_K_M ""
```

Then confirm it's fully in VRAM:
```bash
nvidia-smi
```
Memory usage should jump to ~48–49GB. If it's significantly lower, layers are being offloaded to CPU — see the troubleshooting section.

---

### Path B — Ollama Image (olla.sh)

Use this when your provider offers a pre-built Ollama image. The image already has Ollama installed and the server running — you only need to pull the model.

📄 **Script:** [`olla.sh`](https://github.com/UbongIsrael/Guides/blob/main/cloud-llm-setup/olla.sh)

#### What the script does:
1. Installs `zstd` and `lshw`
2. Pulls `qwen3-coder-next:q4_K_M` directly (Ollama server already running)

#### Environment variables to set on the provider dashboard (before deployment):

| Variable | Value |
|---|---|
| `OLLAMA_HOST` | `0.0.0.0:11434` |
| `OLLAMA_KEEP_ALIVE` | `-1` |

Set these in your provider's container configuration UI before deploying. They ensure Ollama binds to all interfaces (not just localhost) and keeps the model resident in VRAM indefinitely.

#### Step-by-step commands:

**Step 1 — SSH into your node**

On Vast.ai, copy the SSH command from the instance's **Connect** button. It will look like:
```bash
ssh -p 19054 root@<IP>
```

**Step 2 — Verify GPU**
```bash
nvidia-smi
```

**Step 3 — Check disk space**
```bash
df -h | grep -v tmpfs
```
Look for the large mounted volume. On Vast.ai this is typically `/workspace`. You need 80GB+ available. See [Section 5](#5-post-setup-storage-fix) if storage is tight.

**Step 4 — Set model storage path**

If root disk is small and your large volume is at `/workspace`:
```bash
export OLLAMA_MODELS=/workspace/ollama/models
mkdir -p /workspace/ollama/models
```

**Step 5 — Verify Ollama is already running**
```bash
curl http://localhost:11434
# Expected: Ollama is running
```

If nothing returns, start it manually:
```bash
ollama serve &
sleep 5
```

**Step 6 — Pull and run the script**
```bash
curl -fsSL https://raw.githubusercontent.com/UbongIsrael/Guides/main/cloud-llm-setup/olla.sh -o olla.sh
chmod +x olla.sh && ./olla.sh
```

**Step 7 — Pre-load the model into VRAM**
```bash
OLLAMA_MODELS=/workspace/ollama/models ollama run qwen3-coder-next:q4_K_M ""
```

Confirm full VRAM usage:
```bash
nvidia-smi
```

---

## 5. Post-Setup: Storage Fix

This is one of the most common issues you'll hit. Cloud containers often have a small root filesystem (20–32GB) and mount the real disk elsewhere.

#### Diagnose the issue
```bash
df -h | grep -v tmpfs
```

Sample output that shows the problem:
```
Filesystem      Size  Used Avail Use%  Mounted on
overlay          32G   32G     0 100%  /           ← full, this is root
/dev/nvme0n1p3  3.5T  1.5T  2.1T  42% /workspace  ← this is where you want to write
```

#### Fix: Point Ollama to the large volume
```bash
export OLLAMA_MODELS=/workspace/ollama/models
mkdir -p /workspace/ollama/models
```

Then re-run your pull:
```bash
ollama pull qwen3-coder-next:q4_K_M
```

#### If you can't find a large volume
Your container's disk allocation may just be too small. On Vast.ai, **destroy the instance** and redeploy — set **Disk Space to 100GB** in the instance configuration before clicking Rent. The default is often 20–32GB which is insufficient.

#### Check which directory has space quickly
```bash
df -h | sort -k4 -rh | head -5
```

---

## 6. Tunnel to Your Local Machine

Once the model is loaded on the cloud server, you need to forward port 11434 to your local machine so OpenCode (or any other tool) can reach it.

#### Get your SSH command

On Vast.ai, click the **Connect** button on your instance. You'll see something like:
```
ssh -p 19054 root@175.155.64x.xxx -L 8080:localhost:8080
```

#### Modify it for Ollama

Replace the port forwarding portion to tunnel 11434:
```bash
ssh -p 19054 root@175.155.64x.xxx -N -L 11434:localhost:11434
```

`-N` means no shell — the terminal stays open just as a tunnel. Leave it running.

#### Verify the tunnel works (new terminal, local machine)

**On macOS / Linux:**
```bash
curl http://localhost:11434/api/tags
```

**On Windows (PowerShell):**
```powershell
curl http://localhost:11434/api/tags
```

You should see a JSON response listing the model:
```json
{"models":[{"name":"qwen3-coder-next:q4_K_M",...}]}
```

If you see this, the full chain — cloud GPU → SSH tunnel → local machine — is working.

---

## 7. Configure OpenCode

OpenCode uses two separate config files. You need to create both.

#### File 1: Provider config

**Path:**
- macOS/Linux: `~/.config/opencode/opencode.jsonc`
- Windows: `%USERPROFILE%\.config\opencode\opencode.jsonc`

**Create on macOS/Linux:**
```bash
mkdir -p ~/.config/opencode
cat > ~/.config/opencode/opencode.jsonc << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "qwen3-coder-next:q4_K_M": {
          "tools": true
        }
      }
    }
  }
}
EOF
```

**Create on Windows (PowerShell):**
```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.config\opencode"

@'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "qwen3-coder-next:q4_K_M": {
          "tools": true
        }
      }
    }
  }
}
'@ | Out-File -FilePath "$env:USERPROFILE\.config\opencode\opencode.jsonc" -Encoding utf8
```

---

#### File 2: Auth config

Ollama doesn't require authentication, but OpenCode expects an entry in the auth file or it will throw an auth error on the first request.

**Path:**
- macOS/Linux: `~/.local/share/opencode/auth.json`
- Windows: `%USERPROFILE%\.local\share\opencode\auth.json`

**Create on macOS/Linux:**
```bash
mkdir -p ~/.local/share/opencode
cat > ~/.local/share/opencode/auth.json << 'EOF'
{
  "ollama": {
    "type": "api",
    "key": "ollama"
  }
}
EOF
```

**Create on Windows (PowerShell):**
```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\share\opencode"

@'
{
  "ollama": {
    "type": "api",
    "key": "ollama"
  }
}
'@ | Out-File -FilePath "$env:USERPROFILE\.local\share\opencode\auth.json" -Encoding utf8
```

---

#### Restart OpenCode and select the model

OpenCode does not hot-reload config. Restart it fully after creating these files, then run:

```
/model ollama/qwen3-coder-next:q4_K_M
```

---

## 8. Assistive & Troubleshooting Commands

These are commands you'll reach for during setup, debugging, and daily use. They're not in the setup scripts but are essential.

---

### Model Management

**List all downloaded models:**
```bash
OLLAMA_MODELS=/workspace/ollama/models ollama list
```

**Remove a model (free up space):**
```bash
OLLAMA_MODELS=/workspace/ollama/models ollama rm qwen3.5:35b
```

**Check model details:**
```bash
OLLAMA_MODELS=/workspace/ollama/models ollama show qwen3-coder-next:q4_K_M
```

---

### Context Window Fix (Important for Agentic Coding)

Ollama defaults to a **4,096 token context window** regardless of what the model supports. For agentic coding, OpenCode sends large prompts — 4K context will cause tool calls to silently fail or truncate mid-session.

Fix: Create a custom model variant with a larger context:

```bash
# On the cloud server
ollama run qwen3-coder-next:q4_K_M
/set parameter num_ctx 32768
/save qwen3-coder-next:32k
/bye
```

Then update your `opencode.jsonc` model key:
```json
"models": {
  "qwen3-coder-next:32k": {
    "tools": true
  }
}
```

Verify the saved model appears:
```bash
OLLAMA_MODELS=/workspace/ollama/models ollama list
```

> Use the exact name shown in `ollama list` — not the name you think you saved it as.

---

### Measure Token Generation Speed

Run this after a model is loaded to see your actual tok/s:

```bash
OLLAMA_MODELS=/workspace/ollama/models ollama run qwen3-coder-next:q4_K_M \
  "write a binary search implementation in TypeScript" --verbose
```

At the end of the output you'll see:
```
eval rate:             18.42 tokens/s
```

This is your real-world generation speed. For a 48GB single GPU with Qwen3-Coder-Next at Q4, expect **15–25 tok/s**. Below 10 tok/s suggests CPU offloading is happening.

---

### Check GPU VRAM Usage

```bash
nvidia-smi
```

**What to look for:**
- Memory usage at ~48–49GB → model fully loaded in VRAM ✅
- Memory usage at 5–10GB → model not loaded yet, run a prompt to warm it
- Memory usage fluctuating up and down → multiple models hot-swapping ⚠️

Watch it live during inference:
```bash
watch -n 1 nvidia-smi
```

---

### Prevent Model Hot-Swapping

If you have multiple models pulled, Ollama may unload and reload between requests, causing 30–60 second delays. Fix:

```bash
# Restart Ollama with a max of 1 loaded model
pkill ollama
sleep 3
export OLLAMA_MODELS=/workspace/ollama/models
export OLLAMA_KEEP_ALIVE=-1
export OLLAMA_MAX_LOADED_MODELS=1
ollama serve > /tmp/ollama.log 2>&1 &
sleep 5

# Pre-warm immediately
ollama run qwen3-coder-next:q4_K_M ""
```

---

### Screen Session Management (Path A / CUDA only)

```bash
# List all screen sessions
screen -ls

# Reattach to the ollama session
screen -r ollama

# Detach without killing (inside screen)
# Press: Ctrl+A, then D

# Kill the session entirely
screen -X -S ollama quit
```

---

### Check Ollama Logs

```bash
# If started with Path B or background &
cat /tmp/ollama.log

# Or tail live
tail -f /tmp/ollama.log
```

---

### Find Your Largest Available Disk Mount

```bash
df -h | grep -v tmpfs | sort -k4 -rh | head -5
```

---

### Verify Environment Variables Are Set

```bash
echo $OLLAMA_HOST
echo $OLLAMA_KEEP_ALIVE
echo $OLLAMA_MODELS
```

---

## 9. Do's and Don'ts

### ✅ Do's

- **Always run `nvidia-smi` first after SSHing in.** Verify the GPU name and VRAM match your rental before running anything. Provider listings can be inaccurate.
- **Always check disk space before pulling a model.** A 51GB model pull on a 32GB disk wastes time and leaves the container broken.
- **Use single-GPU setups for 48GB-class models.** A single RTX 6000 Ada or RTX 5880 Ada will outperform a 4× consumer multi-GPU PCIe setup at the same VRAM.
- **Set `OLLAMA_KEEP_ALIVE=-1` always.** This keeps the model in VRAM between requests. Without it, Ollama unloads after 5 minutes of inactivity and you get a cold-start delay on every new OpenCode session.
- **Pre-warm the model after starting Ollama.** Run a blank prompt (`ollama run <model> ""`) so it's loaded before your first real request.
- **Use `--verbose` to measure tok/s.** Know your baseline speed. If it drops significantly between sessions, Ollama may have unloaded the model.
- **Set context window to at least 32K for agentic use.** The default 4K will silently break tool calling on large codebases.
- **Spin down the cloud node when not working.** You only pay for hours the GPU is running. Stop the instance when you're done for the day.
- **Keep your SSH tunnel terminal open.** The tunnel dies when that terminal closes. Consider running it in a separate persistent terminal or `tmux` session on your local machine.

---

### ❌ Don'ts

- **Don't trust the TFLOPS number as the headline spec.** Memory bandwidth and VRAM capacity matter far more for LLM inference.
- **Don't use 4-way PCIe consumer GPU setups for large models.** The all-reduce overhead and fragmented VRAM per card will give you slower inference than a single professional GPU at the same price.
- **Don't assume the VRAM in a listing is accurate.** There is no RTX 4090 with 48GB VRAM. If a listing says that, SSH in and run `nvidia-smi` before running anything.
- **Don't pull multiple large models without checking available disk.** Two 50GB models fill 100GB instantly. Use `ollama rm <model>` to remove models you're not using.
- **Don't leave multiple large models pulled if you only use one.** Ollama may hot-swap between them, causing 30–60 second reload delays between OpenCode requests.
- **Don't set the context window above what your VRAM can support.** KV cache for long contexts takes VRAM. A 128K context with a 51GB model on a 48GB GPU will OOM. 32K is a safe ceiling for this hardware tier.
- **Don't close the SSH tunnel terminal mid-session.** OpenCode will lose connection to the model instantly. If using Windows Terminal, pin the tunnel session to a separate pane.
- **Don't rely on provider-facing ports (like 8080 from the Vast dashboard).** Those are for HTTP services. Always forward port 11434 explicitly in your SSH command.

---

## 10. Contact

Built and maintained by **Sheikh** (Digital Sheikh)

- **X / Twitter:** [@0xBonge](https://x.com/0xBonge)
- **Email:** [sheikhthefather@gmail.com](mailto:sheikhthefather@gmail.com)
- **Portfolio:** [digitalsheikh.co](https://digitalsheikh.co)
- **GitHub:** [github.com/UbongIsrael](https://github.com/UbongIsrael)

Found an issue with the guide or have a setup that worked differently? Open an issue or PR on the [Guides repo](https://github.com/UbongIsrael/Guides) — contributions welcome.

---

*Last updated: April 2026. GPU pricing, model benchmarks, and provider features change frequently — verify before committing to a setup.*