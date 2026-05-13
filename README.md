# Guides by Sheikh

Practical, deployment-tested guides for developers — covering self-hosted AI infrastructure, cloud tooling, and engineering workflows. Each guide is written from real build experience, including the errors and fixes along the way.

---

## Guides

### 🖥️ [Cloud LLM Setup — Self-Hosted Agentic Coding](./cloud-llm-setup/)

> Run open-weight LLMs on a cloud GPU, tunnel them to your local machine, and use them as a coding agent via OpenCode.

Covers GPU evaluation (VRAM, bandwidth, single vs multi-GPU, NVLink), model recommendations, two setup paths (CUDA image and Ollama image), SSH tunneling, OpenCode configuration, storage troubleshooting, context window tuning, and a full command reference.

**Models covered:** Qwen3-Coder-Next 80B, MiniMax M2.5, Qwen3.5, Kimi K2.5, GLM-5
**Tested on:** Vast.ai · RTX 5880 Ada 48GB
**Scripts:** [`setup.sh`](./cloud-llm-setup/setup.sh) · [`olla.sh`](./cloud-llm-setup/olla.sh)

---

### 🖥️ [Linux Desktop Streaming — VPS Remote Desktop](./full-linux-desktop+stream/)

> Set up a full Linux desktop on a cloud VPS, accessible via browser or VNC client. Uses Lubuntu + TigerVNC + noVNC.

Covers use cases (region-bound access, persistent dev environments, privacy-sensitive browsing), server provider selection, Contabo recommendation with region picking guide, step-by-step setup, HTTPS configuration with custom domain, service management commands, and security considerations.

**Tested on:** Contabo VPS, Pay as you Use GPUs on Vast.ai and OctaSpace Cube · Ubuntu 22.04/24.04
**Script:** [`setup-desktop.sh`](./full-linux-desktop+stream/setup-desktop.sh)

---

## About

Written and maintained by **Sheikh** (Digital Sheikh)

- **X / Twitter:** [@0xBonge](https://x.com/0xBonge)
- **Email:** [sheikhthefather@gmail.com](mailto:sheikhthefather@gmail.com)
- **Portfolio:** [digitalsheikh.co](https://digitalsheikh.co)
- **GitHub:** [github.com/UbongIsrael](https://github.com/UbongIsrael)

More guides coming. If something helped you or you found an issue, open a PR or reach out directly.