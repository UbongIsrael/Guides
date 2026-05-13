#!/bin/bash

# =============================================================================
# VPS Remote Desktop Setup — Lubuntu + TigerVNC + noVNC
# =============================================================================
# Usage: sudo bash setup-desktop.sh
# Tested on: Ubuntu 22.04 / 24.04
# =============================================================================

set -e

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
VNC_DISPLAY=":1"
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

# ── Step 1: System update ─────────────────────────────────────────────────────
section "[1/6] Updating system packages..."
apt-get update -qq && apt-get upgrade -y -qq
log "System updated"

# ── Step 2: Lubuntu desktop ───────────────────────────────────────────────────
section "[2/6] Installing Lubuntu desktop (LXQt)..."
info "This may take a few minutes..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    lubuntu-desktop \
    --no-install-recommends
log "Lubuntu desktop installed"

# ── Step 3: TigerVNC ─────────────────────────────────────────────────────────
section "[3/6] Installing TigerVNC server..."
apt-get install -y -qq tigervnc-standalone-server tigervnc-common
log "TigerVNC installed"

# ── Step 4: noVNC + websockify ────────────────────────────────────────────────
section "[4/6] Installing noVNC + websockify..."
apt-get install -y -qq novnc python3-websockify
log "noVNC installed"

# ── Step 5: Configure VNC ─────────────────────────────────────────────────────
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

# ── Step 6: Systemd services ──────────────────────────────────────────────────
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
cat > /etc/systemd/system/vncserver@.service << EOF
[Unit]
Description=TigerVNC server (display %i)
After=syslog.target network.target

[Service]
Type=forking
User=$RUN_USER
WorkingDirectory=$USER_HOME
PIDFile=$USER_HOME/.vnc/%H:%i.pid
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

# noVNC service — binds to localhost only (nginx proxies it if HTTPS chosen)
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
    --listen 127.0.0.1:$NOVNC_PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vncserver@1.service
systemctl enable novnc.service
systemctl start vncserver@1.service

info "Waiting for VNC to initialize..."
sleep 4

systemctl start novnc.service
log "Core services started"

# =============================================================================
# OPTIONAL: Google Chrome (.deb binary)
# =============================================================================
if [[ "$INSTALL_CHROME" == "y" ]]; then
    section "[Optional] Installing Google Chrome (binary .deb)..."
    info "Downloading Chrome .deb directly from Google..."

    CHROME_DEB="/tmp/google-chrome-stable.deb"

    # Pull the .deb straight from Google — no snap, no PPA, no middlemen
    curl -fsSL -o "$CHROME_DEB" \
        "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"

    # Install and auto-resolve any missing dependencies
    apt-get install -y -qq "$CHROME_DEB" || apt-get install -f -y -qq

    rm -f "$CHROME_DEB"

    # Chrome refuses to launch as root without --no-sandbox
    # Create a wrapper so it just works without manual flags every time
    if [[ "$RUN_USER" == "root" ]]; then
        cat > /usr/local/bin/chrome << 'WRAPPER'
#!/bin/bash
/usr/bin/google-chrome-stable --no-sandbox "$@"
WRAPPER
        chmod +x /usr/local/bin/chrome
        warn "Running as root — '--no-sandbox' wrapper created at /usr/local/bin/chrome"
        warn "Consider creating a non-root user for desktop sessions in production."
    fi

    log "Google Chrome installed (binary .deb)"
    info "Launch from the desktop app menu or terminal: google-chrome-stable"
fi

# =============================================================================
# OPTIONAL: nginx + certbot HTTPS
# =============================================================================
if [[ "$INSTALL_HTTPS" == "y" ]]; then
    section "[Optional] Setting up nginx + Let's Encrypt HTTPS..."

    apt-get install -y -qq nginx certbot python3-certbot-nginx

    # nginx config: reverse proxy noVNC with WebSocket support
    cat > /etc/nginx/sites-available/novnc << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    # Certbot challenge passthrough
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Redirect all HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN_NAME;

    # SSL (populated by certbot)
    ssl_certificate     /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    # Proxy to noVNC
    location / {
        proxy_pass         http://127.0.0.1:$NOVNC_PORT;
        proxy_http_version 1.1;

        # WebSocket upgrade headers — noVNC will not work without these
        proxy_set_header Upgrade    \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host       \$host;

        # Long timeouts so the session doesn't drop
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/novnc /etc/nginx/sites-enabled/novnc
    rm -f /etc/nginx/sites-enabled/default

    nginx -t && systemctl reload nginx
    log "nginx configured for $DOMAIN_NAME"

    info "Requesting SSL certificate from Let's Encrypt..."
    certbot --nginx \
        -d "$DOMAIN_NAME" \
        --email "$LE_EMAIL" \
        --agree-tos \
        --non-interactive \
        --redirect
    log "SSL certificate issued"

    # Open HTTP/HTTPS ports in UFW
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        ufw allow 80/tcp  > /dev/null
        ufw allow 443/tcp > /dev/null
        log "UFW: ports 80 and 443 opened"
    fi

    # Daily auto-renewal cron
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | crontab -
    log "SSL auto-renewal cron added (runs daily at 3am)"

    ACCESS_URL="https://$DOMAIN_NAME/vnc.html"

else
    # No HTTPS — expose noVNC directly on all interfaces
    sed -i "s/127.0.0.1:$NOVNC_PORT/$NOVNC_PORT/" /etc/systemd/system/novnc.service
    systemctl daemon-reload
    systemctl restart novnc.service

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

# ── Service status ────────────────────────────────────────────────────────────
echo ""
info "Service status:"
systemctl is-active --quiet vncserver@1.service \
    && echo -e "  ${GREEN}vncserver${NC}   running" \
    || echo -e "  ${RED}vncserver${NC}   FAILED — run: journalctl -u vncserver@1 -n 30"

systemctl is-active --quiet novnc.service \
    && echo -e "  ${GREEN}novnc${NC}       running" \
    || echo -e "  ${RED}novnc${NC}       FAILED — run: journalctl -u novnc -n 30"

[[ "$INSTALL_HTTPS" == "y" ]] && {
    systemctl is-active --quiet nginx \
        && echo -e "  ${GREEN}nginx${NC}       running" \
        || echo -e "  ${RED}nginx${NC}       FAILED — run: journalctl -u nginx -n 30"
}

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║              Setup Complete!             ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo -e ""
echo -e "  ${BOLD}Desktop access:${NC}"
echo -e "  ${YELLOW}$ACCESS_URL${NC}"
echo -e ""
[[ "$INSTALL_CHROME" == "y" ]] && \
echo -e "  ${BOLD}Chrome:${NC}      installed (binary .deb)"
[[ "$INSTALL_HTTPS"  == "y" ]] && \
echo -e "  ${BOLD}HTTPS:${NC}       enabled — nginx + Let's Encrypt"
echo -e "  ${BOLD}Resolution:${NC}  $RESOLUTION"
echo -e "  ${BOLD}User:${NC}        $RUN_USER"
echo -e ""
echo -e "  ${CYAN}Useful commands:${NC}"
echo -e "  systemctl status vncserver@1      # VNC status"
echo -e "  systemctl status novnc            # noVNC status"
echo -e "  systemctl restart vncserver@1     # restart VNC"
echo -e "  vncserver -list                   # list active sessions"
[[ "$INSTALL_HTTPS" == "y" ]] && \
echo -e "  certbot renew --dry-run           # test SSL auto-renewal"
echo ""