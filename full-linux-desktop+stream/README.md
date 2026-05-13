# Linux Desktop Streaming Setup Guide

### By Sheikh — Remote Desktop on Cloud VPS with Lubuntu + TigerVNC + noVNC

> A practical guide for setting up a full Linux desktop environment on a cloud VPS, accessible through any browser. Uses Lubuntu (lightweight LXQt desktop), TigerVNC for the remote display server, and noVNC for browser-based access without plugins.

---

## Table of Contents

1. [Overview](#1-overview)
2. [What This Setup Does](#2-what-this-setup-does)
3. [Use Cases](#3-use-cases)
   - [When Do You Need a Remote Desktop?](#when-do-you-need-a-remote-desktop)
   - [Region-Bound Access](#region-bound-access)
4. [Server Provider Selection](#4-server-provider-selection)
   - [Why Contabo](#why-contabo)
   - [Picking the Right Region](#picking-the-right-region)
5. [Prerequisites](#5-prerequisites)
6. [Step-by-Step Setup](#6-step-by-step-setup)
7. [Accessing Your Desktop](#7-accessing-your-desktop)
   - [Browser Access (noVNC)](#browser-access-novnc)
   - [Direct VNC Client](#direct-vnc-client)
8. [Optional: HTTPS with Custom Domain](#8-optional-https-with-custom-domain)
9. [Service Management](#9-service-management)
10. [Security Considerations](#10-security-considerations)
11. [Troubleshooting](#11-troubleshooting)
12. [Contact](#12-contact)

---

## 1. Overview

This guide walks through deploying a full Linux desktop environment on a cloud VPS. Your desktop runs entirely on the remote server — you access it through your browser (noVNC) or any VNC client. The entire desktop session, applications, and data live on the VPS, not your local machine.

**Target OS:** Ubuntu 22.04 / 24.04  
**Desktop Environment:** Lubuntu (LXQt) — lightweight, fast, low resource  
**VNC Server:** TigerVNC  
**Web Access:** noVNC (browser-based, no plugins)  
**Tested on:** Contabo VPS, Pay as you Use GPUs on Vast.ai and OctaSpace Cube  
**Script:** [`setup-desktop.sh`](./setup-desktop.sh)

---

## 2. What This Setup Does

The setup script (`setup-desktop.sh`) performs the following:

1. **System Update** — Updates all packages to latest versions
2. **Installs Lubuntu Desktop** — Lightweight LXQt desktop environment (~800MB)
3. **Installs TigerVNC** — Standalone VNC server and client tools
4. **Installs noVNC + websockify** — Web-based VNC client with WebSocket proxy
5. **Configures VNC** — Sets up password, display resolution (1280x800), color depth (24-bit)
6. **Creates systemd services** — Auto-starts VNC and noVNC on boot
7. **Optional: Google Chrome** — Installs via official .deb binary (not snap)
8. **Optional: HTTPS** — Sets up nginx + Let's Encrypt with a custom domain

The script is interactive — it prompts you for:
- Whether to install Google Chrome
- Whether to set up HTTPS with a domain
- VNC password (6-8 characters)

---

## 3. Use Cases

### When Do You Need a Remote Desktop?

A cloud desktop is useful in many scenarios:

| Use Case | Why Remote Desktop Helps |
|---|---|
| **Region-bound services** | Some services (banking APIs, local e-commerce, government portals) only allow access from specific countries. A VPS in that region gives you a local IP. |
| **Persistent development environment** | Keep your dev environment running 24/7 without draining your local machine's battery or keeping your laptop awake. Access from any device. |
| **Browser-based work with local feel** | Run Chrome/Firefox on the VPS with full desktop environment — faster than remote browser streaming services. |
| **Privacy-sensitive browsing** | Isolate browsing from your local machine. Your local machine never sees the traffic — everything stays on the VPS. |
| **Cross-platform access** | Access a full Linux desktop from Windows, macOS, Android, or iOS — any device with a browser. |
| **Running GUI tools on Linux** | Use Linux-only GUI applications (GIMP, Blender, Kdenlive, etc.) without dual-booting or VMs. |
| **Long-running tasks** | Download large files, run batch processing, encoding, or compilations that take hours — no need to keep your laptop on. |

### Region-Bound Access

Many services restrict access based on geographic location:
- **Banking portals** — Only accessible from within the country
- **Government services** — Tax portals, business registration systems
- **E-commerce platforms** — Some only ship to domestic addresses or block foreign IPs
- **Streaming services** — Content licensing restrictions by region

A VPS in the target region gives you an IP address from that country, bypassing these restrictions. This is one of the most practical use cases for a remote desktop.

---

## 4. Server Provider Selection

### Why Contabo

[Contabo](https://contabo.com) is a German cloud provider that offers excellent value for VPS instances with generous resources at low monthly rates.

**Why this guide uses Contabo:**
- **Competitive pricing** — VPS with 8 vCPU, 30GB RAM, 400GB SSD starting around €5-7/month
- **Multiple regions** — German (Germany), US (St. Louis, New York, Seattle), Singapore
- **Simple billing** — Monthly flat rate, no per-hour fluctuations
- **IPv4 included** — Each VPS gets a dedicated IPv4 address
- **No setup fees** — Instant provisioning

For a desktop streaming setup, the recommended minimum specs:
- **vCPU:** 4+ cores
- **RAM:** 8GB+ (16GB recommended for comfortable desktop use)
- **Storage:** 100GB+ SSD
- **Bandwidth:** Unmetered or generous quota

> **Note:** Contabo requires identity verification (credit card or PayPal) for signup. Not ideal if you need complete anonymity, but excellent for reliability.

### Picking the Right Region

The server region matters significantly for two reasons:

#### 1. Latency

Your desktop experience depends on network latency between you and the VPS. The closer the server is to your physical location, the better.

| Your Location | Recommended Contabo Region |
|---|---|
| Europe | Germany (Düsseldorf) |
| US East Coast | New York or St. Louis |
| US West Coast | Seattle |
| Asia | Singapore |

Test latency before committing: ping the IP ranges from your location. Contabo displays server IPs in their control panel.

#### 2. Region-Bound Access

If your goal is accessing region-locked services, pick a VPS in that exact region:

- **Germany** — For EU banking, government services, European streaming
- **US (St. Louis/New York)** — For US-only services, US banking apps
- **US (Seattle)** — Lower latency for US West Coast users
- **Singapore** — For Asian services, Southeast Asian banking/e-commerce

> **Pro tip:** When targeting a specific country's services, always pick a VPS located in **that country**, not just a nearby region. Some services check the country of the IP address specifically, and a nearby country may still be flagged as foreign.

---

## 5. Prerequisites

Before running the setup script:

1. **A VPS with Ubuntu 22.04 or 24.04** — Fresh install recommended
2. **SSH access to the VPS** — Root or sudo access
3. **A domain (optional)** — Required only if you want HTTPS access
4. **At least 4 vCPU, 8GB RAM** — For comfortable desktop performance
5. **Firewall ports open** — If your provider has a firewall, open:
   - Port 6080 (noVNC HTTP)
   - Port 5901 (VNC)
   - Port 80/443 (if using HTTPS)

---

## 6. Step-by-Step Setup

**Step 1 — SSH into your VPS**
```bash
ssh root@YOUR_VPS_IP
```

**Step 2 — Download the setup script**
```bash
curl -fsSL https://raw.githubusercontent.com/UbongIsrael/cloud-llm-setup/main/full-linux-desktop+stream/setup-desktop.sh -o setup-desktop.sh
```

**Step 3 — Run the script**
```bash
chmod +x setup-desktop.sh
sudo bash setup-desktop.sh
```

**Step 4 — Follow the prompts**

The script will ask:
- Install Google Chrome? `[y/N]`
- Set up HTTPS with nginx + certbot? `[y/N]`
  - If yes: enter your domain name
  - If yes: enter your email for Let's Encrypt
- Set VNC password (6-8 characters)

**Step 5 — Note the access URL**

At the end, the script displays your access URL:
- **Without HTTPS:** `http://YOUR_VPS_IP:6080/vnc.html`
- **With HTTPS:** `https://your-domain.com/vnc.html`

---

## 7. Accessing Your Desktop

### Browser Access (noVNC)

The easiest method — no software needed on your local machine.

1. Open the access URL in any modern browser (Chrome, Firefox, Edge, Safari)
2. You'll see the noVNC login page
3. Enter the VNC password you set during setup
4. Click "Connect"

You're now viewing your remote Lubuntu desktop in the browser.

**Keyboard tips in noVNC:**
- Ctrl+Alt+Del sends the key combination to the remote desktop
- Use the noVNC toolbar (top) for special keys, clipboard, fullscreen

### Direct VNC Client

For lower latency and better performance, use a VNC client:

| OS | Client |
|---|---|
| Windows | [TigerVNC Viewer](https://tigervnc.org) · [RealVNC](https://realvnc.com) |
| macOS | [TigerVNC Viewer](https://tigervnc.org) · [RealVNC](https://realvnc.com) |
| Linux | `apt install tigervnc-viewer` then `vncviewer YOUR_VPS_IP:5901` |
| Android | [VNC Viewer - Remote Desktop](https://play.google.com/store/apps/details?id=com.realvnc.viewer.android) |
| iOS | [VNC Viewer](https://apps.apple.com/app/vnc-viewer/id897443893) |

**Connection details:**
- Host: `YOUR_VPS_IP`
- Port: `5901`
- Password: Whatever you set during setup

---

## 8. Optional: HTTPS with Custom Domain

If you want secure, encrypted access:

1. **Point your domain at your VPS IP** — Add an A record in your DNS provider:
   - Type: `A`
   - Name: `desktop` (or your preferred subdomain)
   - Value: `YOUR_VPS_IP`

2. **Run the setup script and choose HTTPS** — When prompted, enter your domain and email

The script will:
- Install nginx and certbot
- Configure nginx as a reverse proxy with WebSocket support
- Obtain a free SSL certificate from Let's Encrypt
- Set up automatic certificate renewal (daily cron at 3am)

**Access your desktop securely:**
```
https://desktop.yourdomain.com/vnc.html
```

**Benefits of HTTPS:**
- Encrypted traffic — safe on public WiFi
- No browser warnings about insecure connection
- Required for some browser features

---

## 9. Service Management

Useful commands for managing your desktop:

| Command | What it does |
|---|---|
| `systemctl status vncserver@1` | Check VNC server status |
| `systemctl restart vncserver@1` | Restart VNC server |
| `systemctl status novnc` | Check noVNC proxy status |
| `systemctl restart novnc` | Restart noVNC proxy |
| `vncserver -list` | List active VNC sessions |
| `vncserver -kill :1` | Kill the display :1 session |
| `certbot renew --dry-run` | Test SSL auto-renewal |
| `journalctl -u vncserver@1 -n 50` | View recent VNC logs |

---

## 10. Security Considerations

1. **Strong VNC password** — Use at least 8 characters with mixed case and numbers
2. **Keep software updated** — The script updates packages on install
3. **Firewall** — If your provider offers firewall rules, only open the ports you need
4. **HTTPS recommended** — Use HTTPS when possible, especially on public networks
5. **Don't run as root in production** — The script supports running as a non-root user; for persistent personal use, create a regular user and run VNC under that account
6. **Domain SSL** — Let's Encrypt certificates auto-renew — but ensure your domain DNS stays valid
7. **Session timeout** — Consider setting up auto-logout after inactivity if sensitive work

---

## 11. Troubleshooting

**noVNC shows "Connecting..." but never connects**
- Check that VNC is running: `systemctl status vncserver@1`
- Check noVNC: `systemctl status novnc`
- Check logs: `journalctl -u vncserver@1 -n 30`

**Black screen after connecting**
- The VNC server started but the desktop environment didn't launch
- Check `$HOME/.vnc/xstartup` exists and is executable
- Try manually starting: `su - YOUR_USER -c "vncserver :1"`

**Chrome won't launch as root**
- The script creates a wrapper at `/usr/local/bin/chrome` with `--no-sandbox`
- If running as a regular user, launch Chrome normally from the app menu

**Very slow desktop response**
- VPS specs too low — aim for 8GB+ RAM, 4 vCPU
- High latency between you and the server region
- Check network: ping your VPS IP

**SSL certificate renewal failing**
- Check certbot logs: `journalctl -u certbot`
- Ensure port 80 is open for Let's Encrypt challenges
- Test renewal: `certbot renew --dry-run`

**VNC password rejected**
- The password is stored in `$HOME/.vnc/passwd`
- Re-run with a new password or manually reset with `vncpasswd`

---

## 12. Contact

Built and maintained by **Sheikh** (Digital Sheikh)

- **X / Twitter:** [@0xBonge](https://x.com/0xBonge)
- **Email:** [sheikhthefather@gmail.com](mailto:sheikhthefather@gmail.com)
- **Portfolio:** [digitalsheikh.co](https://digitalsheikh.co)
- **GitHub:** [github.com/UbongIsrael](https://github.com/UbongIsrael)

Found an issue with the guide or have a setup that worked differently? Open an issue or PR on the [Guides repo](https://github.com/UbongIsrael/Guides) — contributions welcome.

---

*Last updated: May 2026. VPS pricing and region availability may change — verify before signing up.*