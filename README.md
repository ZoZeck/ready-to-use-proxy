# 1-Command 3proxy Deploy

A self-contained script to **instantly** deploy a private [3proxy](https://github.com/3proxy/3proxy) proxy server on any fresh Ubuntu/Debian machine.

This script was co-developed and debugged with the help of an AI assistant, focusing on maximum reliability and user-friendliness.

## 🔥 The "One Command" Method

This is the only method you need. Connect to your new server via SSH, and paste the following command. It will download the latest version of the script and execute it, handling everything from installation to verification.

```bash
bash <(curl -sL https://raw.githubusercontent.com/ZoZeck/ready-to-use-proxy/main/deploy.sh)
```

#### **Optional: Specify a Port**

To use a custom port, simply add it to the end of the command:
```bash
bash <(curl -sL https://raw.githubusercontent.com/ZoZeck/ready-to-use-proxy/main/deploy.sh) 8080
```

---

## ✨ What It Does

-   **Runs Everywhere**: Works on any fresh Debian or Ubuntu server by compiling from source.
-   **User-Friendly**: Provides clear, step-by-step output and only shows detailed logs if an error occurs.
-   **Self-Contained**: The script has no external dependencies besides standard build tools. The proxy test is embedded within it.
-   **Secure**: Generates a random username and password.
-   **Reliable**: Sets up a `systemd` service for auto-start and stability.
-   **Verified**: Automatically tests the proxy connection to ensure it's working before giving you the credentials.
-   **Clean**: Saves credentials to `/root/3proxy_credentials.txt` and automatically cleans up all temporary files.

---

## 📂 Project Structure

The project is intentionally minimalist. The `deploy.sh` script is all you need.

```text
.
├── README.md       # This guide
└── deploy.sh       # The all-in-one, self-contained deployment script
```