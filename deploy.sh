#!/bin/bash

# 1-Command 3proxy Deploy Script (with source compilation for maximum compatibility)
# A self-contained script to install, configure, and test 3proxy.
#
# Usage:
#   bash <(curl -sL https://.../deploy.sh) [PORT]

# --- Configuration & Colors ---
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

# --- Helper Functions ---
function error_exit() {
    echo -e "${RED}❌ ERROR: $1${NC}" >&2
    exit 1
}

function check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error_exit "This script must be run as root (or with sudo)."
    fi
}

# --- Main Logic Functions ---

function install_dependencies() {
    echo -e "${YELLOW}📦 Installing required packages (git, build-essential, curl, python3-pip)...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq git build-essential curl python3 python3-pip >/dev/null || error_exit "Failed to install dependencies."
}

# --- MODIFIED: Compiles 3proxy from source for universal compatibility ---
function install_3proxy() {
    echo -e "${YELLOW}🛠️  Cloning and compiling 3proxy from source (this may take a few minutes)...${NC}"
    
    cd /opt || error_exit "Cannot change directory to /opt"
    rm -rf 3proxy
    # Using the correct, new repository URL for git clone
    git clone --depth 1 https://github.com/3proxy/3proxy.git || error_exit "Failed to clone 3proxy repository. Check network connection to github.com."
    cd 3proxy || error_exit "Cannot change directory to /opt/3proxy"
    
    make -f Makefile.Linux || error_exit "Failed to compile 3proxy."
    
    install -m 755 bin/3proxy /usr/local/bin/
    mkdir -p /etc/3proxy/ /var/log/3proxy
}

function configure_3proxy() {
    echo -e "${YELLOW}📝 Creating configuration files and systemd service...${NC}"
    cat > /etc/3proxy/3proxy.cfg <<EOF
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log /var/log/3proxy/3proxy.log D
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
auth strong
users $USERNAME:CL:$PASSWORD
allow $USERNAME
proxy -n -a -p$PORT -i0.0.0.0 -e$VDS_IP
flush
EOF

    cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy proxy server
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
}

function start_and_test_proxy() {
    echo -e "${YELLOW}▶️  Starting and verifying the proxy service...${NC}"
    systemctl daemon-reload
    systemctl enable 3proxy >/dev/null 2>&1
    systemctl restart 3proxy
    sleep 3

    if ! systemctl is-active --quiet 3proxy; then
        journalctl -u 3proxy --no-pager -n 20
        error_exit "3proxy service failed to start. See logs above."
    fi

    local TEST_SCRIPT
    TEST_SCRIPT=$(mktemp --suffix=.py)
    trap 'rm -f "$TEST_SCRIPT"' EXIT

    cat > "$TEST_SCRIPT" << 'PYTHON_EOF'
import sys, requests

def main():
    if len(sys.argv) != 5: sys.exit(1)
    host, port, user, password = sys.argv[1:]
    proxy_url = f"http://{user}:{password}@{host}:{port}"
    proxies = {"http": proxy_url, "https": proxy_url}
    test_url = "https://api.ipify.org?format=json"
    print(f"[*] Testing proxy {host}:{port}...")
    try:
        response = requests.get(test_url, proxies=proxies, timeout=15)
        response.raise_for_status()
        result_ip = response.json().get("ip")
        print(f"[+] Success! Response IP: {result_ip}")
        if result_ip == host:
            print(f"[+] SUCCESS: Response IP matches proxy IP.")
            sys.exit(0)
        else:
            print(f"[!] ERROR: Response IP ({result_ip}) does not match proxy IP ({host}).")
            sys.exit(1)
    except Exception as e:
        print(f"[!] FATAL: Proxy test failed. Details: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
PYTHON_EOF
    
    pip3 install requests -q --disable-pip-version-check
    
    if ! python3 "$TEST_SCRIPT" "$VDS_IP" "$PORT" "$USERNAME" "$PASSWORD"; then
        error_exit "Proxy connection test FAILED. Check your firewall or 3proxy logs."
    fi
}

function print_summary() {
    echo -e "\n${GREEN}🎉 Done! Proxy server is ready to use.${NC}"
    echo "-----------------------------------------------------"
    echo -e "🔗 Address:  ${YELLOW}$VDS_IP${NC}"
    echo -e "🚪 Port:     ${YELLOW}$PORT${NC}"
    echo -e "👤 Login:    ${YELLOW}$USERNAME${NC}"
    echo -e "🔑 Password: ${YELLOW}$PASSWORD${NC}"
    echo "-----------------------------------------------------"
    
    local creds_file="/root/3proxy_credentials.txt"
    echo "$VDS_IP:$PORT:$USERNAME:$PASSWORD" > "$creds_file"
    echo -e "📄 Connection details saved to ${YELLOW}${creds_file}${NC}"
}

# --- Main Execution ---
main() {
    check_root
    
    USERNAME="user$(tr -dc a-z0-9 </dev/urandom | head -c6)"
    PASSWORD="$(tr -dc A-Za-z0-9 </dev/urandom | head -c12)"
    PORT=${1:-3128}
    VDS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com)
    [ -z "$VDS_IP" ] && error_exit "Could not detect external IPv4 address."

    echo -e "${GREEN}🚀 Starting 1-Command 3proxy deployment...${NC}"
    echo "   Server IP: $VDS_IP | Proxy Port: $PORT"

    install_dependencies
    install_3proxy
    configure_3proxy
    start_and_test_proxy
    
    if ufw status | grep -q "Status: active"; then
        ufw allow "$PORT/tcp" >/dev/null
    fi
    
    print_summary
}

main "$@"