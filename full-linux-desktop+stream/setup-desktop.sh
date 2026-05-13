#!/bin/bash

# =============================================================================
# VPS Remote Desktop Setup — Lubuntu + TigerVNC + noVNC
# =============================================================================
# Usage: sudo bash setup-desktop.sh
# Tested on: Ubuntu 22.04 / 24.04
# =============================================================================

# No set -e — we handle errors explicitly so one failure doesn't kill the run

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✔]${NC} $1"; }
info()   { echo -e "${CYAN}[→]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
fail()   { echo -e "${RED}[✘]${NC} $1"; exit 1; }
section(){ echo -e "\n${BOLD}$1${NC}"; }
prompt() { echo -e "${CYAN}$1${NC}"; }

echo -e "\n${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   VPS Desktop Streaming Setup Script     ║${NC}"
echo -e "${BOLD}║   Lubuntu + TigerVNC + noVNC             ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}\n"

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && fail "Run this script as root: sudo bash $0"

# ── Detect user ───────────────────────────────────────────────────────────────
if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
    RUN_USER="$SUDO_USER"
else
    RUN_USER="root"
fi
USER_HOME=$(eval echo "~$RUN_USER")
info "Running setup for user: ${BOLD}$RUN_USER${NC} (home: $USER_HOME)"

# ── Config ────────────────────────────────────────────────────────────────────
VNC_PORT=5901
NOVNC_PORT=6080
RESOLUTION="1280x800"
COLOR_DEPTH=24

# ── Pre-flight: optional steps ────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Optional steps — answer before we begin:${NC}"
echo ""

prompt "Install Google Chrome (via .deb binary — recommended over snap)? [y/N]: "
read -r INSTALL_CHROME
INSTALL_CHROME="${INSTALL_CHROME,,}"

prompt "Set up HTTPS with nginx + certbot (needs a domain pointed at this VPS)? [y/N]: "
read -r INSTALL_HTTPS
INSTALL_HTTPS="${INSTALL_HTTPS,,}"

if [[ "$INSTALL_HTTPS" == "y" ]]; then
    prompt "Enter your domain name (e.g. desktop.yourdomain.com): "
    read -r DOMAIN_NAME
    [[ -z "$DOMAIN_NAME" ]] && warn "No domain entered — skipping HTTPS setup." && INSTALL_HTTPS="n"

    if [[ "$INSTALL_HTTPS" == "y" ]]; then
        prompt "Enter your email for Let's Encrypt notifications: "
        read -r LE_EMAIL
        [[ -z "$LE_EMAIL" ]] && warn "No email entered — skipping HTTPS setup." && INSTALL_HTTPS="n"
    fi
fi

# ── VNC Password ──────────────────────────────────────────────────────────────
echo ""
while true; do
    read -s -p "$(echo -e ${CYAN})Set VNC password (6-8 chars): $(echo -e ${NC})" VNC_PASS
    echo
    [[ ${#VNC_PASS} -ge 6 ]] && break
    warn "Password must be at least 6 characters. Try again."
done

# =============================================================================
# CORE SETUP
# =============================================================================

section "[1/6] Updating system packages..."
apt-get update -qq && apt-get upgrade -y -qq
log "System updated"

section "[2/6] Installing Lubuntu desktop (LXQt)..."
info "This may take a few minutes..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    lubuntu-desktop \
    --no-install-recommends
log "Lubuntu desktop installed"

section "[3/6] Installing TigerVNC server..."
apt-get install -y -qq tigervnc-standalone-server tigervnc-common
log "TigerVNC installed"

section "[4/6] Installing noVNC + websockify..."
apt-get install -y -qq novnc python3-websockify
log "noVNC installed"

section "[5/6] Configuring VNC..."

mkdir -p "$USER_HOME/.vnc"
echo "$VNC_PASS" | vncpasswd -f > "$USER_HOME/.vnc/passwd"
chmod 600 "$USER_HOME/.vnc/passwd"

cat > "$USER_HOME/.vnc/xstartup" << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=LXQt

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
fi

exec startlxqt
EOF
chmod +x "$USER_HOME/.vnc/xstartup"
chown -R "$RUN_USER:$RUN_USER" "$USER_HOME/.vnc"
log "VNC config written to $USER_HOME/.vnc/"

section "[6/6] Creating systemd services..."

# Detect novnc_proxy path
NOVNC_PROXY=""
for path in \
    /usr/share/novnc/utils/novnc_proxy \
    /usr/share/novnc/utils/launch.sh \
    $(which novnc_proxy 2>/dev/null); do
    [[ -x "$path" ]] && NOVNC_PROXY="$path" && break
done
[[ -z "$NOVNC_PROXY" ]] && fail "novnc_proxy not found. Check noVNC installation."
info "noVNC proxy at: $NOVNC_PROXY"

# VNC server service
# Note: PIDFile is intentionally omitted — newer TigerVNC versions write the
# PID file with a different naming scheme than systemd expects, causing false
# failures even when the server is running fine.
cat > /etc/systemd/system/vncserver@.service << EOF
[Unit]
Description=TigerVNC server (display %i)
After=syslog.target network.target

[Service]
Type=forking
User=$RUN_USER
WorkingDirectory=$USER_HOME
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver \\
    -depth $COLOR_DEPTH \\
    -geometry $RESOLUTION \\
    -localhost no \\
    :%i
ExecStop=/usr/bin/vncserver -kill :%i
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# noVNC service — binds to localhost only when HTTPS is chosen, all interfaces otherwise
if [[ "$INSTALL_HTTPS" == "y" ]]; then
    NOVNC_LISTEN="127.0.0.1:$NOVNC_PORT"
else
    NOVNC_LISTEN="$NOVNC_PORT"
fi

cat > /etc/systemd/system/novnc.service << EOF
[Unit]
Description=noVNC WebSocket proxy
After=vncserver@1.service
Requires=vncserver@1.service

[Service]
Type=simple
User=$RUN_USER
ExecStart=$NOVNC_PROXY \\
    --vnc localhost:$VNC_PORT \\
    --listen $NOVNC_LISTEN
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vncserver@1.service
systemctl enable novnc.service

# Start VNC and wait for it to bind to its port
info "Starting VNC server..."
systemctl start vncserver@1.service || true
info "Waiting for VNC to bind to port $VNC_PORT..."
for i in $(seq 1 15); do
    ss -tlnp | grep -q ":$VNC_PORT" && break
    sleep 1
done

if ! ss -tlnp | grep -q ":$VNC_PORT"; then
    warn "VNC did not bind to port $VNC_PORT in time."
    warn "Check logs: journalctl -u vncserver@1 -n 30"
    warn "Or manually: cat $USER_HOME/.vnc/*.log"
    warn "Continuing — fix VNC then run: systemctl start novnc.service"
else
    log "VNC is listening on port $VNC_PORT"
fi

# Start noVNC and verify
info "Starting noVNC..."
systemctl start novnc.service || true
sleep 3

if ss -tlnp | grep -q ":$NOVNC_PORT"; then
    log "noVNC is listening on port $NOVNC_PORT"
else
    warn "noVNC did not start. Check: journalctl -u novnc -n 30"
fi

# =============================================================================
# OPTIONAL: Google Chrome (.deb binary)
# =============================================================================
if [[ "$INSTALL_CHROME" == "y" ]]; then
    section "[Optional] Installing Google Chrome (binary .deb)..."
    info "Downloading Chrome .deb directly from Google..."

    CHROME_DEB="/tmp/google-chrome-stable.deb"
    curl -fsSL -o "$CHROME_DEB" \
        "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"

    apt-get install -y -qq "$CHROME_DEB" || apt-get install -f -y -qq
    rm -f "$CHROME_DEB"

    # Chrome refuses to launch as root without --no-sandbox
    if [[ "$RUN_USER" == "root" ]]; then
        cat > /usr/local/bin/chrome << 'WRAPPER'
#!/bin/bash
/usr/bin/google-chrome-stable --no-sandbox "$@"
WRAPPER
        chmod +x /usr/local/bin/chrome
        warn "Running as root — '--no-sandbox' wrapper created at /usr/local/bin/chrome"
    fi

    log "Google Chrome installed (binary .deb)"
fi

# =============================================================================
# OPTIONAL: nginx + certbot HTTPS
# =============================================================================
if [[ "$INSTALL_HTTPS" == "y" ]]; then
    section "[Optional] Setting up nginx + Let's Encrypt HTTPS..."

    apt-get install -y -qq nginx certbot python3-certbot-nginx

    # HTTP-only config first — certbot will inject the SSL block itself
    # Do NOT pre-write the ssl_certificate lines before the cert exists
    cat > /etc/nginx/sites-available/novnc << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        proxy_pass         http://127.0.0.1:$NOVNC_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host       \$host;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/novnc /etc/nginx/sites-enabled/novnc
    rm -f /etc/nginx/sites-enabled/default

    if nginx -t; then
        systemctl enable --now nginx
        log "nginx started"
    else
        warn "nginx config test failed — check /etc/nginx/sites-available/novnc"
    fi

    info "Requesting SSL certificate from Let's Encrypt..."
    if certbot --nginx \
        -d "$DOMAIN_NAME" \
        --email "$LE_EMAIL" \
        --agree-tos \
        --non-interactive \
        --redirect; then
        log "SSL certificate issued"
        # Auto-renewal cron
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | crontab -
        log "SSL auto-renewal cron added (daily at 3am)"
        ACCESS_URL="https://$DOMAIN_NAME/vnc.html"
    else
        warn "certbot failed — DNS may not have propagated yet."
        warn "Once DNS is ready, run manually:"
        warn "  certbot --nginx -d $DOMAIN_NAME --email $LE_EMAIL --agree-tos --non-interactive --redirect"
        ACCESS_URL="http://$DOMAIN_NAME/vnc.html (HTTPS pending)"
    fi

    # Open HTTP/HTTPS in UFW
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        ufw allow 80/tcp  > /dev/null
        ufw allow 443/tcp > /dev/null
        log "UFW: ports 80 and 443 opened"
    fi

else
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        ufw allow "$NOVNC_PORT/tcp" > /dev/null
        ufw allow "$VNC_PORT/tcp"   > /dev/null
        log "UFW: ports $NOVNC_PORT and $VNC_PORT opened"
    else
        warn "UFW not active. Open these ports in your VPS firewall/control panel:"
        warn "  TCP $NOVNC_PORT  (noVNC web access)"
        warn "  TCP $VNC_PORT    (direct VNC, optional)"
    fi

    VPS_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "YOUR_VPS_IP")
    ACCESS_URL="http://$VPS_IP:$NOVNC_PORT/vnc.html"
fi

# =============================================================================
# FINAL HEALTH CHECK
# =============================================================================
section "Health Check"

HEALTH_OK=true

# VNC port
if ss -tlnp | grep -q ":$VNC_PORT"; then
    echo -e "  ${GREEN}[✔]${NC} VNC        — port $VNC_PORT bound"
else
    echo -e "  ${RED}[✘]${NC} VNC        — port $VNC_PORT NOT bound"
    echo -e "       Fix: journalctl -u vncserver@1 -n 30"
    echo -e "            cat $USER_HOME/.vnc/*.log"
    HEALTH_OK=false
fi

# noVNC port
if ss -tlnp | grep -q ":$NOVNC_PORT"; then
    echo -e "  ${GREEN}[✔]${NC} noVNC      — port $NOVNC_PORT bound"
else
    echo -e "  ${RED}[✘]${NC} noVNC      — port $NOVNC_PORT NOT bound"
    echo -e "       Fix: journalctl -u novnc -n 30"
    HEALTH_OK=false
fi

# systemd service states
for svc in vncserver@1 novnc; do
    if systemctl is-active --quiet "$svc"; then
        echo -e "  ${GREEN}[✔]${NC} $svc service — active"
    else
        echo -e "  ${RED}[✘]${NC} $svc service — INACTIVE"
        HEALTH_OK=false
    fi
done

# nginx (if installed)
if [[ "$INSTALL_HTTPS" == "y" ]]; then
    if systemctl is-active --quiet nginx; then
        echo -e "  ${GREEN}[✔]${NC} nginx      — active"
    else
        echo -e "  ${RED}[✘]${NC} nginx      — INACTIVE"
        echo -e "       Fix: journalctl -u nginx -n 30"
        HEALTH_OK=false
    fi
fi

# Chrome (if installed)
if [[ "$INSTALL_CHROME" == "y" ]]; then
    if command -v google-chrome-stable &>/dev/null; then
        echo -e "  ${GREEN}[✔]${NC} Chrome     — installed"
    else
        echo -e "  ${YELLOW}[!]${NC} Chrome     — not found in PATH (may still be installed)"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}╔══════════════════════════════════════════╗${NC}"
if [[ "$HEALTH_OK" == "true" ]]; then
    echo -e "${BOLD}║         Setup Complete — All Good!       ║${NC}"
else
    echo -e "${BOLD}║    Setup Done — Some Services Need Fix   ║${NC}"
fi
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo -e ""
echo -e "  ${BOLD}Desktop access:${NC}"
echo -e "  ${YELLOW}$ACCESS_URL${NC}"
echo -e ""
[[ "$INSTALL_CHROME" == "y" ]] && echo -e "  ${BOLD}Chrome:${NC}      installed (binary .deb)"
[[ "$INSTALL_HTTPS"  == "y" ]] && echo -e "  ${BOLD}HTTPS:${NC}       nginx + Let's Encrypt"
echo -e "  ${BOLD}Resolution:${NC}  $RESOLUTION"
echo -e "  ${BOLD}User:${NC}        $RUN_USER"
echo -e ""
echo -e "  ${CYAN}Useful commands:${NC}"
echo -e "  systemctl status vncserver@1      # VNC status"
echo -e "  systemctl status novnc            # noVNC status"
echo -e "  vncserver -list                   # list active sessions"
echo -e "  journalctl -u vncserver@1 -n 30   # VNC logs"
[[ "$INSTALL_HTTPS" == "y" ]] && \
echo -e "  certbot renew --dry-run           # test SSL renewal"
echo ""