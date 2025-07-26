#!/bin/bash
#
#  Hey there! This script will set up a 3proxy server for you.
#  It's designed to be run on a fresh Debian or Ubuntu box.
#  We'll compile it from source to make sure it works everywhere.
#  Just run it, grab a coffee, and you'll have a proxy in a few minutes.
#
#  - ZoZeck's friendly neighborhood sysadmin
#

# --- Safety First! ---
# Exit immediately if a command fails, or if we use an unset variable.
set -e
set -u

# --- Let's add some color ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Global variables & Cleanup ---
# Define TEST_SCRIPT here so it's globally available for the trap
TEST_SCRIPT=""
# This 'trap' makes sure we clean up the temp file, no matter what.
trap 'rm -f "$TEST_SCRIPT"' EXIT


# --- A little helper for printing steps ---
function print_step() {
    echo -e "\n${BLUE}➤ $1${NC}"
}

# --- A better error message ---
function error_exit() {
    echo -e "\n${RED}=============================================${NC}"
    echo -e "${RED}❌ Oh no! Something went wrong.${NC}"
    echo -e "${RED}Error: $1${NC}"
    echo -e "${RED}=============================================${NC}"
    exit 1
}


# --- THE MAIN EVENT ---
function main() {

    # Gotta be root to do this stuff.
    if [[ "$(id -u)" -ne 0 ]]; then
        error_exit "This script needs to be run as root. Try 'sudo ./deploy.sh'"
    fi

    clear
    echo -e "${GREEN}==========================================="
    echo "  🚀 Let's get you a shiny new proxy!  "
    echo -e "===========================================${NC}"

    # --- Step 1: Install the tools we need ---
    print_step "First, let's grab the necessary tools (git, compiler, etc.)."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq git build-essential curl python3-pip >/dev/null || error_exit "Couldn't install the required packages. Check your internet connection or 'apt'."
    echo "✅ Tools are ready."

    # --- Step 2: Get 3proxy and build it ---
    print_step "Downloading the latest 3proxy code and compiling it."
    echo "This is the part that takes a minute or two..."

    cd /opt || error_exit "Couldn't switch to /opt directory."
    rm -rf 3proxy # Clean up any old attempts

    git clone --depth 1 https://github.com/3proxy/3proxy.git >/dev/null || error_exit "Failed to download the source code from GitHub."
    cd 3proxy || error_exit "Something went wrong after downloading the code."
    
    make -f Makefile.Linux >/dev/null || error_exit "The compilation failed. You might be on an unsupported OS."
    
    install -m 755 bin/3proxy /usr/local/bin/
    echo "✅ 3proxy is compiled and installed."

    # --- Step 3: Create the configuration ---
    print_step "Setting up the configuration file."
    
    local USERNAME="user$(tr -dc a-z0-9 </dev/urandom | head -c6)"
    local PASSWORD
    PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c12)
    local PORT=${1:-3128}
    local VDS_IP
    VDS_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com)

    if [[ -z "$VDS_IP" ]]; then
        error_exit "Couldn't figure out your server's public IP address."
    fi

    mkdir -p /etc/3proxy/ /var/log/3proxy

    cat > /etc/3proxy/3proxy.cfg <<EOF
# --- 3proxy Config ---
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
auth strong
users $USERNAME:CL:$PASSWORD
allow $USERNAME
proxy -n -a -p$PORT -i0.0.0.0 -e$VDS_IP
log /var/log/3proxy/3proxy.log D
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
EOF
    echo "✅ Config file created."

    # --- Step 4: Set up the service to run automatically ---
    print_step "Creating a systemd service to keep the proxy running."
    
    cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Tiny Proxy Server
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
    echo "✅ Systemd service is ready."


    # --- Step 5: Start it up and test it! ---
    print_step "Let's fire it up and make sure it actually works."
    systemctl daemon-reload
    systemctl enable 3proxy >/dev/null 2>&1
    systemctl restart 3proxy
    
    sleep 3

    if ! systemctl is-active --quiet 3proxy; then
        journalctl -u 3proxy --no-pager -n 20
        error_exit "The 3proxy service failed to start. The logs above might tell you why."
    fi

    echo "Running a quick connection test..."
    # Assign the temp file path to the global variable
    TEST_SCRIPT=$(mktemp --suffix=.py)

    cat > "$TEST_SCRIPT" << PYTHON_EOF
import sys, requests
try:
    host, port, user, password = sys.argv[1:]
    proxy_url = f"http://{user}:{password}@{host}:{port}"
    test_url = "https://api.ipify.org"
    proxies = {"http": proxy_url, "https": proxy_url}
    ip = requests.get(test_url, proxies=proxies, timeout=10).text
    if ip == host:
        print(f"Success! The world sees you as {ip}")
        sys.exit(0)
    else:
        print(f"Error: Proxy IP mismatch. Expected {host}, got {ip}")
        sys.exit(1)
except Exception as e:
    print(f"Fatal error during test: {e}")
    sys.exit(1)
PYTHON_EOF

    # Use apt to install requests, the "right" way for modern Debian/Ubuntu
    apt-get install -y -qq python3-requests >/dev/null
    
    if ! python3 "$TEST_SCRIPT" "$VDS_IP" "$PORT" "$USERNAME" "$PASSWORD"; then
        error_exit "The proxy was installed, but the connection test failed. Check your firewall!"
    fi
    echo "✅ Connection test passed with flying colors!"

    # --- Final Step: The Grand Finale ---
    if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
        print_step "UFW firewall is active. Opening port $PORT for you."
        ufw allow "$PORT/tcp" >/dev/null
    fi

    local creds_file="/root/3proxy_credentials.txt"
    echo "$VDS_IP:$PORT:$USERNAME:$PASSWORD" > "$creds_file"

    echo -e "\n${GREEN}==========================================="
    echo -e "      🎉 All done! You're ready to go. 🎉"
    echo -e "===========================================${NC}"
    echo -e "Here are your credentials. Keep them safe!"
    echo -e "-------------------------------------------"
    echo -e "  Address:  ${YELLOW}$VDS_IP${NC}"
    echo -e "  Port:     ${YELLOW}$PORT${NC}"
    echo -e "  Login:    ${YELLOW}$USERNAME${NC}"
    echo -e "  Password: ${YELLOW}$PASSWORD${NC}"
    echo -e "-------------------------------------------"
    echo -e "A copy has been saved to: ${YELLOW}$creds_file${NC}"
    echo ""
}

# And... action!
main "$@"