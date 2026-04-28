# Cloud-Hosted LLM Setup for Agentic Coding via OpenCode
### April 2026 — Self-Host First, API as Fallback

---

## Table of Contents

1. [The Landscape in April 2026](#1-the-landscape-in-april-2026)
2. [Model Shortlist — Who Made the Cut](#2-model-shortlist--who-made-the-cut)
3. [Benchmark Comparisons](#3-benchmark-comparisons)
4. [VRAM Reality Check](#4-vram-reality-check)
5. [Cloud GPU Pricing (Pay-as-You-Go)](#5-cloud-gpu-pricing-pay-as-you-go)
6. [Attainable Setup Tiers](#6-attainable-setup-tiers)
7. [OpenCode Tunnel Setup](#7-opencode-tunnel-setup)
8. [Quick Decision Matrix](#8-quick-decision-matrix)
9. [What to Actually Do](#9-what-to-actually-do)

---

## 1. The Landscape in April 2026

February 2026 was a watershed moment. Within a single month, four Chinese labs shipped open-weight models that erased the gap between open-source and frontier proprietary models. The key shift: **Mixture-of-Experts (MoE) architecture** lets these models carry 200B–1T total parameters while only *activating* 3B–40B per token — keeping inference cost and VRAM manageable relative to model quality.

The result: you can now run a model that scores within **1–2 percentage points** of Claude Opus 4.6 on SWE-bench Verified on a 2× H100 setup you're renting for ~$3–4/hr. A year ago, nothing in that class existed outside Anthropic and OpenAI's closed APIs.

The models you asked about — **Kimi, MiniMax, Qwen** — are precisely the ones at the center of this shift. Here's everything you need to pick a setup.

---

## 2. Model Shortlist — Who Made the Cut

These are the models worth your attention for agentic coding in 2026, filtered for self-hosting viability.

### 🥇 MiniMax M2.5
> **The efficiency king. Closest open-weight model to Claude Opus 4.6 on SWE-bench.**

- **Architecture:** 229B total parameters, only **10B active per token** (MoE)
- **License:** Apache 2.0 (fully commercial, no restrictions)
- **Context window:** 1M tokens
- **SWE-bench Verified:** 80.2% (Claude Opus 4.6 sits at 80.8%)
- **Self-hosting:** vLLM or SGLang recommended. Quantized Q4 fits in ~2× H100 80GB
- **Speed at production:** Up to 100+ tokens/sec on high-speed variant
- **Why it matters:** The 10B active parameter count means you get near-frontier quality at *a fraction* of the compute cost of similarly-sized dense models. M2.5-highspeed is a separate variant optimized for throughput.

---

### 🥈 Kimi K2.5
> **Best ceiling performance. Native vision. Agent Swarm is genuinely novel.**

- **Architecture:** 1T total parameters, **32B active per token** (MoE), 384 experts
- **License:** Modified MIT (open for commercial use; attribution required above 100M MAU or $20M MRR — not your concern)
- **Context window:** 256K tokens
- **SWE-bench Verified:** 76.8% (standard) — hits higher on LiveCodeBench (85%) and leads open-source on CorpFin
- **Self-hosting:** 8× H200 for full FP16 — **not cheap**. However, Unsloth GGUF Q2_K_XL (~375GB) can run on a single A100 with heavy CPU offloading (~5–10 tok/s). Realistic for personal coding, not production.
- **Agent Swarm:** Can coordinate up to 100 parallel sub-agents; claims 4.5× speedup on parallelizable tasks — no other open-source model offers this
- **Vision:** Native, trained from scratch (not bolted on)
- **Weakness:** Slowest of the peer group at ~38 tokens/sec on API; verbose output inflates token costs
- **Why it matters:** If you're doing frontend-heavy, visual coding, or complex multi-file agentic tasks — this is the model. Not the most cost-efficient self-host but worth knowing.

---

### 🥉 Qwen3-Coder-Next (80B MoE)
> **The practical champion for solo devs. Runs on a single ~48GB machine.**

- **Architecture:** 80B total parameters, **3B active per token** (MoE)
- **License:** Apache 2.0
- **Context window:** 128K (extendable)
- **SWE-bench Verified:** 70.6%
- **Self-hosting:** Single machine with ~46GB memory — **most attainable setup**. Runs on a rented L40S (48GB) or A100 80GB with headroom.
- **Ecosystem:** Full Ollama, vLLM, llama.cpp, LM Studio, SGLang support. Plug-and-play.
- **Why it matters:** You get a competitive coding model on $0.31–0.80/hr hardware. For solo development work in a tool like OpenCode, 70.6% SWE-bench is genuinely excellent. The 3B active parameter count means fast inference even on mid-range GPUs.

---

### Qwen3-Coder 480B (Full Size)
> **Max Qwen quality, but needs serious infrastructure.**

- **Architecture:** 480B total, 35B active per token
- **License:** Apache 2.0
- **SWE-bench Verified:** 67–70% (slightly *below* Qwen3-Coder-Next — efficiency tradeoff)
- **Self-hosting:** ~960GB VRAM for FP16. Needs 8× H100 or 6× H200. Expensive.
- **Verdict:** Skip for self-hosting unless you have a cluster. Use via DashScope API instead.

---

### Qwen3.5 (General Flagship)
> **Released February 2026. Better than Qwen3 across the board, adds native vision.**

- **Architecture:** 397B total, 17B active (MoE), Apache 2.0
- **Coding score:** 91.3% on LiveCodeBench — **beats Kimi K2.5** on this benchmark
- **Context window:** 1M tokens
- **Self-hosting:** 4× A100 80GB (quantized) or 2× H100 SXM for reasonable throughput
- **Why it matters:** If benchmarks are your north star, Qwen3.5 leads open-source on coding as of April 2026. The tradeoff vs Coder-Next: needs more iron.

---

### GLM-5 (Honorable Mention)
> **MIT licensed, strong SWE-bench, solid on debugging.**

- **Architecture:** 744B total, 40B active, MIT license
- **SWE-bench Verified:** 77.8% — leads open-source on this specific benchmark
- **Self-hosting:** ~1.49TB BF16 / ~595GB INT4. Needs 4× H200 for full quality. Trained on Huawei Ascend chips but runs on NVIDIA fine.
- **Verdict:** Strong contender but hardware requirements are steep. GLM-5.1 at $3/month via subscription is the more practical path for most devs.

---

### DeepSeek V3.2 (Budget Reference)
> **The cheapest path to serious coding capability.**

- **SWE-bench Verified:** 73%, MIT license
- **API cost:** $0.28/M input, $0.42/M output — cheapest in this class
- **Self-hosting:** ~685B, needs significant cluster. Best used via API (Fireworks, Together.ai, DeepInfra)
- **Why it's here:** If you're running a tight budget and want an API fallback, DeepSeek V3.2 is your best value option by far.

---

## 3. Benchmark Comparisons

### SWE-bench Verified (Real Codebase Bug Fixing)
*SWE-bench is the most respected coding benchmark — it tests models on real GitHub issues.*

| Model | SWE-bench Verified | Notes |
|---|---|---|
| **Claude Opus 4.6** | **80.8–80.9%** | Proprietary ceiling |
| **Claude Sonnet 4.6** | **79.6%** | Near-Opus at lower cost |
| **MiniMax M2.5** | **80.2%** | Open-weight — within 0.6pts of Opus |
| **GLM-5** | **77.8%** | MIT, best open-source on raw SWE-bench |
| **Kimi K2.5** | **76.8%** | Leads on LiveCodeBench & agent tasks |
| **Qwen3.5-397B** | **~78–80%** | Estimated; leads LiveCodeBench at 91.3% |
| **DeepSeek V3.2** | **73%** | Strong for price |
| **Qwen3-Coder-Next** | **70.6%** | Remarkable for hardware needed |
| **Gemini 2.5 Pro** | ~80% | Proprietary, strong but pricey |
| **GPT-5.4** | ~82% | Proprietary frontier |

> ⚠️ Note: All SWE-bench scores are self-reported or from standardized third-party harnesses. Absolute numbers carry noise; relative rankings are more reliable. SWE-bench Pro (1,865 multi-language tasks) is emerging as the more rigorous alternative.

---

### HumanEval / LiveCodeBench (Code Generation)

| Model | HumanEval | LiveCodeBench | 
|---|---|---|
| Claude Opus 4.6 | ~92% | ~88% |
| Qwen3.5 | ~91% | **91.3%** |
| Kimi K2.5 | ~87% | **85%** |
| MiniMax M2.5 | ~84% | ~82% |
| GLM-5 | **94.2%** | ~83% |
| Qwen3-Coder-Next | ~81% | ~78% |

---

### Context Window

| Model | Context | Practical Use |
|---|---|---|
| Qwen3.5 | 1M tokens | Entire medium-sized codebase |
| MiniMax M2.5 | 1M tokens | Full repo context |
| Kimi K2.5 | 256K tokens | Large files / multi-file |
| Qwen3-Coder-Next | 128K | Most coding tasks |
| Claude Sonnet/Opus 4.6 | 200K | Mid-range |
| Gemini 2.5 Pro | 1M | Full repo |

---

## 4. VRAM Reality Check

> VRAM listed is for **full-precision (FP16/BF16) inference**. Quantized (INT4/Q4) typically cuts requirements by 50–65%.

| Model | Full Precision | INT4 / Q4_K_M | Minimum Practical Setup |
|---|---|---|---|
| **Qwen3-Coder-Next 80B** | ~160GB | **~46GB** | Single L40S 48GB ✅ |
| **Qwen3.5-27B** | ~54GB | **~18–22GB** | Single RTX 4090 24GB ✅ |
| **MiniMax M2.5** | ~460GB | **~160GB** | 2× H100 80GB (INT4) |
| **Kimi K2.5** | ~2TB | **~375GB (Q2)** | 8× H100+ (full), or CPU offload on single GPU (slow) |
| **Qwen3.5-397B** | ~794GB | **~280GB** | 4× A100 80GB (INT4) |
| **GLM-5** | ~1,490GB | **~595GB** | 4× H200 141GB |
| **Qwen3-Coder 480B** | ~960GB | ~350GB | 4–6× H100 |

**Key insight:** MoE architecture changes the game. MiniMax M2.5 has 229B total parameters but only activates 10B per token — so INT4 inference on 2× H100 (160GB total) is actually comfortable. You're not running a 229B dense model; you're running effectively a 10B model from a 229B library.

---

## 5. Cloud GPU Pricing (Pay-as-You-Go)

> All prices are approximate as of April 2026. Marketplace prices (Vast.ai, RunPod community) fluctuate based on availability.

### GPU Tiers

| GPU | VRAM | RunPod (Secure) | RunPod (Community) | Vast.ai |
|---|---|---|---|---|
| RTX 4090 | 24GB | ~$0.74/hr | ~$0.44/hr | ~$0.30–0.45/hr |
| L40S | 48GB | ~$0.69/hr | ~$0.45/hr | **~$0.31/hr** |
| A100 PCIe | 40GB | $0.60/hr | ~$0.38/hr | $0.52/hr |
| A100 SXM | 80GB | $0.79/hr | ~$0.50/hr | $0.67/hr |
| H100 PCIe | 80GB | $1.50/hr | ~$0.90/hr | $1.55/hr |
| H100 SXM | 80GB | $2.39–2.99/hr | ~$1.50/hr | ~$1.80/hr |
| H200 SXM | 141GB | $3.59/hr | — | ~$3.20/hr |
| 2× H100 SXM | 160GB | ~$5.38/hr | ~$3.20/hr | ~$3.50/hr |
| 4× A100 SXM | 320GB | ~$3.16/hr | ~$2.00/hr | ~$2.40/hr |

### Alternative Providers

| Provider | Specialty | Notes |
|---|---|---|
| **Vast.ai** | Cheapest marketplace | L40S at $0.31/hr is unbeatable for Qwen3-Coder-Next |
| **RunPod** | Reliable, great UX, fast setup | Best for spinning up quickly |
| **Lambda Labs** | On-demand only, strong H100/A100 availability | No spot pricing |
| **DataCrunch** | H100 at $1.99/hr | Significantly under RunPod on H100 |
| **Spheron** | Spot + enterprise SLA | B200 spot at $2.12/hr for future use |
| **Novita AI** | Cheap A100 options, good for MiniMax | Good docs for MoE models |

### Estimated Daily/Monthly Costs (8hrs active/day)

| Setup | GPU | Hours/Day | Daily Cost | Monthly (~22 days) |
|---|---|---|---|---|
| Budget | Vast.ai L40S × 1 | 8 | ~$2.50 | ~$55 |
| Budget+ | RunPod A100 80GB × 1 | 8 | ~$6.30 | ~$140 |
| Mid | RunPod H100 SXM × 1 | 8 | ~$22 | ~$480 |
| Pro | RunPod 2× H100 SXM | 8 | ~$43 | ~$950 |
| Extreme | RunPod 4× H100 SXM | 8 | ~$86 | ~$1,900 |

> 💡 **Pro tip:** You only need the cloud GPU running while you're actively coding. Spin up → code → spin down. Don't leave it idle overnight.

---

## 6. Attainable Setup Tiers

### 🟢 Tier 1 — Budget (< $5/day)

**Hardware:** 1× Vast.ai L40S 48GB @ ~$0.31/hr  
**Model:** Qwen3-Coder-Next 80B (INT4, ~46GB)  
**Inference:** Ollama or vLLM  
**Speed:** ~20–35 tok/s  
**SWE-bench:** ~70.6%  
**Comparison:** Competes with Qwen3-Coder 32B; significantly better than GPT-4o on most coding tasks from 2025  

**Best for:** Solo devs, daily coding sessions, JavaScript/TypeScript heavy work, most typical agentic tasks in OpenCode

```bash
# Quick start on L40S
curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen3-coder:80b-instruct-q4_K_M
ollama serve --host 0.0.0.0:11434
```

**Monthly estimate:** ~$55 (8hrs/day, 22 working days)

---

### 🟡 Tier 2 — Mid (~$5–15/day)

**Hardware:** 1× DataCrunch or Vast.ai H100 80GB @ $1.99–2.50/hr  
**Model:** Qwen3.5-27B (FP16, ~54GB fits with minor quant) or Qwen3-Coder-Next with full context  
**Inference:** vLLM with tensor parallelism  
**Speed:** ~40–60 tok/s  
**SWE-bench:** ~73–76%  
**Comparison:** Matches DeepSeek V3.2, approaching Kimi K2.5 territory  

**Best for:** Larger codebases, long sessions with extensive context, multi-file refactoring

```bash
# vLLM setup on H100
pip install vllm
python -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen3-Coder-Next-80B-Instruct \
  --tensor-parallel-size 1 \
  --quantization awq \
  --port 8000 \
  --host 0.0.0.0
```

**Monthly estimate:** ~$160–350 (8hrs/day, 22 working days)

---

### 🟠 Tier 3 — Pro (~$20–45/day)

**Hardware:** 2× RunPod H100 SXM 80GB @ ~$5.38/hr  
**Model:** MiniMax M2.5 (INT4, ~160GB fits across 2× H100)  
**Inference:** SGLang (recommended for MoE) or vLLM with tensor parallelism  
**Speed:** ~50–80 tok/s  
**SWE-bench:** ~80.2% — **within 0.6% of Claude Opus 4.6**  
**Comparison:** Near-parity with Claude Opus 4.6. Beats Claude Sonnet 4.6 on SWE-bench.  

**Best for:** Production-grade agentic coding, complex architecture work, large-scale refactors  

```bash
# SGLang server for MiniMax M2.5
pip install "sglang[all]"
python -m sglang.launch_server \
  --model-path MiniMaxAI/MiniMax-M2.5 \
  --tp 2 \
  --quantization int4 \
  --host 0.0.0.0 \
  --port 8000
```

**Monthly estimate:** ~$950 (8hrs/day, 22 working days) — at this point, compare against Claude Code Pro ($20/mo) seriously

---

### 🔴 Tier 4 — Extreme (Not Recommended for Solo)

**Hardware:** 4× H100 or 4× H200 SXM  
**Models:** GLM-5, Kimi K2.5 (full quality), Qwen3-Coder 480B  
**Monthly cost:** $1,500–3,000+ even with careful usage  
**Verdict:** Only makes sense for teams amortizing the cost across multiple developers, or if you have very high-volume agentic workloads running 24/7. At this price point, a Claude Code team plan is more rational.

---

## 7. OpenCode Tunnel Setup

OpenCode supports any OpenAI-compatible endpoint. The workflow is:

```
Cloud GPU (vLLM/Ollama) → SSH Tunnel / Cloudflare Tunnel → localhost → OpenCode
```

### Option A: SSH Reverse Tunnel (Simplest)

On your cloud instance:
```bash
# Start the model server (e.g., Ollama)
ollama serve --host 127.0.0.1:11434
```

On your local machine:
```bash
# Forward cloud port 11434 to localhost:11434
ssh -N -L 11434:localhost:11434 user@<cloud-ip>
```

Then in OpenCode config (`~/.opencode/config.json`):
```json
{
  "providers": {
    "custom": {
      "apiBase": "http://localhost:11434/v1",
      "apiKey": "ollama",
      "model": "qwen3-coder:80b-instruct-q4_K_M"
    }
  }
}
```

---

### Option B: Cloudflare Tunnel (Persistent, No Exposed Ports)

Better for sessions that need to persist or if you're on a dynamic IP.

```bash
# On cloud instance — install cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# Expose vLLM endpoint
cloudflared tunnel --url http://localhost:8000
# → Returns: https://your-tunnel-id.trycloudflare.com
```

Then in OpenCode:
```json
{
  "providers": {
    "self-hosted": {
      "apiBase": "https://your-tunnel-id.trycloudflare.com/v1",
      "apiKey": "Bearer none",
      "model": "qwen3-coder-next"
    }
  }
}
```

---

### Option C: ngrok (Quickest for Dev Sessions)

```bash
# Cloud instance
ngrok http 11434
# → Returns: https://abc123.ngrok.io

# Then in OpenCode
# apiBase: https://abc123.ngrok.io/v1
```

---

### vLLM Endpoint Compatibility

vLLM exposes an OpenAI-compatible API at `/v1`. OpenCode, Roo Code, and most agentic tools speak this natively.

```bash
# Test your endpoint locally (on cloud)
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-coder-next",
    "messages": [{"role": "user", "content": "Write a hello world in Rust"}]
  }'
```

---

### Model String References for OpenCode

| Model | vLLM model string | Ollama tag |
|---|---|---|
| Qwen3-Coder-Next 80B | `Qwen/Qwen3-Coder-Next-80B-Instruct` | `qwen3-coder:80b-q4` |
| Qwen3.5-27B | `Qwen/Qwen3.5-27B-Instruct` | `qwen3.5:27b` |
| MiniMax M2.5 | `MiniMaxAI/MiniMax-M2.5` | *(no Ollama tag yet)* |
| Kimi K2.5 (quantized) | `moonshotai/Kimi-K2.5-GGUF` | *(llama.cpp/GGUF only)* |
| DeepSeek V3.2 | `deepseek-ai/DeepSeek-V3-0324` | `deepseek-v3:latest` |

---

## 8. Quick Decision Matrix

| Scenario | Recommended Setup |
|---|---|
| Tight budget, just want to ship | Vast.ai L40S + Qwen3-Coder-Next 80B |
| Best model that fits one GPU | H100 80GB + Qwen3.5-27B or Qwen3-Coder-Next |
| Closest to Claude Opus quality | 2× H100 + MiniMax M2.5 INT4 |
| Need 1M token context | MiniMax M2.5 or Qwen3.5 API (DashScope) |
| Frontend/visual coding | Kimi K2.5 API ($0.60/$2.50 per M tokens) |
| Lowest API cost fallback | DeepSeek V3.2 ($0.28/$0.42 per M tokens) |
| Team splitting costs | Pro tier (2× H100) amortized |

---

## 9. What to Actually Do

Given your setup — solo dev, using OpenCode for agentic coding, building web/mobile products with complex codebases — here's the practical recommendation:

### Start Here (Week 1)
Spin up a **Vast.ai L40S** ($0.31/hr). Deploy **Qwen3-Coder-Next 80B** via Ollama. Tunnel via SSH. Spend ~$10–15 testing it on your actual workflows (Ticketer backend, Lore agent marketplace). See if 70% SWE-bench quality is enough for your daily work.

### Upgrade Path
If Coder-Next feels limiting on complex multi-file tasks, move to a **single H100 80GB** on DataCrunch ($1.99/hr) and run **Qwen3.5-27B or 72B** (quantized). This hits ~73–76% quality at manageable cost.

### Ceiling Setup (When Projects Justify It)
For sustained production agentic work, **2× H100 + MiniMax M2.5** is the only open-weight setup that gets you to Claude Opus 4.6 territory (80.2% vs 80.8%). At ~$43/day for 8hrs, this is comparable to paying for Claude Code Pro + heavy API usage.

### API Fallback Config (Keep in Reserve)
Always keep a `~/.opencode/config.json` profile for **Kimi K2.5 API** (`$0.60/$2.50/M tokens`) and **DeepSeek V3.2** (`$0.28/$0.42/M tokens`). When your cloud GPU is spun down and you need a quick answer, these are your fastest fallbacks — both are OpenAI-compatible drop-in replacements.

```json
// ~/.opencode/config.json — multi-provider setup
{
  "providers": {
    "local": {
      "apiBase": "http://localhost:11434/v1",
      "apiKey": "none",
      "model": "qwen3-coder:80b-q4"
    },
    "kimi-fallback": {
      "apiBase": "https://api.moonshot.cn/v1",
      "apiKey": "YOUR_KIMI_KEY",
      "model": "kimi-k2.5-instruct"
    },
    "deepseek-fallback": {
      "apiBase": "https://api.deepseek.com/v1",
      "apiKey": "YOUR_DEEPSEEK_KEY",
      "model": "deepseek-chat"
    }
  },
  "defaultProvider": "local"
}
```

---

*Last updated: April 2026. GPU pricing and model benchmarks shift frequently — always verify on provider pages before committing to a setup.*