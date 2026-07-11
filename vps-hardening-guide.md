# First Steps: Harden a New VPS

Quick checklist to secure a freshly spun-up server. Do these in order; **finish SSH key setup and test before disabling password login**, or you may lock yourself out.

**Scope:** Written for Debian/Ubuntu; RHEL/CentOS/Alma/Rocky differences noted where relevant.

**Goal:** Updates, firewall, non-root user, SSH keys only, custom SSH port, no root login, auto security updates, then Tailscale-only access with SSH off the public internet.

**If you get locked out:** Use your provider’s **recovery console** (serial/VNC in the control panel) to log in as root and fix SSH or firewall rules.

---

## 1. Update the system

```bash
sudo apt update && sudo apt upgrade -y
```

*(Debian/Ubuntu. On CentOS/RHEL/Alma/Rocky: `sudo dnf update -y` or `sudo yum update -y`.)*

---

## 2. Firewall

Allow **port 22** for now (default SSH) so you can complete sections 3–4. In **section 5** you’ll move SSH to a custom port (e.g. `2222`) and then remove port 22 from the firewall.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw enable
sudo ufw status
```

---

## 3. Fail2ban (optional but recommended)

Limits brute force on SSH (and any future services). After section 8, SSH is only on Tailscale; fail2ban still applies to auth failures in the logs.

```bash
sudo apt install fail2ban -y
```

Use the **same port** as SSH (e.g. 2222). Create a local jail override:

```bash
sudo nano /etc/fail2ban/jail.local
```

Add only the following lines (no code-fence or extra formatting):

```ini
[sshd]
enabled = true
port = 2222
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 1h
```

Then:

```bash
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
sudo systemctl status fail2ban
```

---

## 4. Create an admin user and SSH key login

**4.1 Create user and add to sudo**

```bash
sudo adduser adminuser
# Debian/Ubuntu:
sudo usermod -aG sudo adminuser
# CentOS/RHEL/Alma/Rocky:
# sudo usermod -aG wheel adminuser
```

**4.2 Generate an SSH key on your laptop/desktop (if you don’t have one)**

On your **local machine** (not the VPS):

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

Accept the default path (`~/.ssh/id_ed25519`) or choose one. Optionally set a passphrase. Then copy your **public** key to the clipboard so you can paste it on the VPS:

- **macOS:** `pbcopy < ~/.ssh/id_ed25519.pub`
- **Linux (X11):** `xclip -selection clipboard < ~/.ssh/id_ed25519.pub` or cat the file and copy manually

*(If you already use a key, use its `.pub` path instead, e.g. `~/.ssh/id_rsa.pub`.)*

**4.3 Put the public key on the VPS (as root or your current user)**

On the **VPS**:

```bash
sudo mkdir -p /home/adminuser/.ssh
sudo chmod 700 /home/adminuser/.ssh
sudo nano /home/adminuser/.ssh/authorized_keys   # paste your public key, save
sudo chmod 600 /home/adminuser/.ssh/authorized_keys
sudo chown -R adminuser:adminuser /home/adminuser/.ssh
```

**4.4 Test login as the new user on port 22 (new terminal; keep current session open)**

SSH is still on the default port until section 5.

```bash
ssh -p 22 adminuser@your-server-ip
sudo whoami   # should print: root
```

If that works, use `adminuser` from here on.

---

## 5. Harden SSH (port, no root, keys only)

Only do this **after** key-based login works for `adminuser` on **port 22**.

**5.1 Allow the new SSH port in the firewall (do this first)**

So you don’t lock yourself out when sshd switches to 2222:

```bash
sudo ufw allow 2222/tcp
sudo ufw reload
sudo ufw status
```

**5.2 Back up sshd_config**

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
```

**5.3 Change SSH to port 2222 and harden**

```bash
sudo nano /etc/ssh/sshd_config
```

Set or add (use port `2222`). Comment out or replace any existing `Port` / `PermitRootLogin` / etc.:

```
Port 2222
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM no
MaxAuthTries 3
AllowUsers adminuser
X11Forwarding no
```

- `AllowUsers adminuser` restricts SSH to that user only; add more space-separated names if needed.
- If you ever need interactive (password) login again, set `UsePAM yes` and re-enable the auth options.

Restart SSH:

```bash
# Debian/Ubuntu:
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
sudo systemctl restart ssh

# CentOS/RHEL/Alma/Rocky:
# sudo systemctl restart sshd
```

**5.4 Test SSH on port 2222, then remove port 22**

In a **new** terminal (from your laptop), test:

```bash
ssh -p 2222 adminuser@your-server-ip
```

Do **not** close your current VPS session until that works. Once you’ve confirmed login on 2222, from the VPS remove port 22 from the firewall:

```bash
sudo ufw delete allow 22/tcp
sudo ufw reload
sudo ufw status
```

From then on, SSH is only on port 2222.

---

## 6. Automatic security updates

**Debian / Ubuntu**

```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades   # select Yes
```

Restrict to **security updates only** (recommended so you don’t get surprise breakage):

```bash
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
```

Set `Unattended-Upgrade::Allowed-Origins` so only the security suite is listed, e.g.:

```
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
```

Remove or comment out other origins (e.g. `-updates`) if you want only security. Optional: automatic reboot when needed (risky on a single VPS):

```
Unattended-Upgrade::Automatic-Reboot "false";
```

**CentOS / RHEL / Alma / Rocky**

```bash
sudo dnf install dnf-automatic -y
sudo sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
sudo systemctl enable --now dnf-automatic.timer
```

---

## 7. Install Tailscale (VPN-only access)

**7.1 Install and join the tailnet**

**Ubuntu:** APT uses your release **codename** (e.g. `noble` for 24.04), not the version number. Get the codename first, then add the key and repo so the correct signing key is used (avoids NO_PUBKEY from copy-paste issues).

**Step 1 — Get your release codename (Ubuntu):**

```bash
lsb_release -cs
```

You should see a single word (e.g. `noble`, `jammy`, `focal`). That is your codename. Optional: see full version info with `lsb_release -a` or `cat /etc/os-release`.

**Step 2 — Add Tailscale key and repo using that codename:**

Replace `CODENAME` in the next block with the output from Step 1 (e.g. `noble`). Or set it in the same shell and run the block as-is:

```bash
CODENAME=$(lsb_release -cs)
curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${CODENAME}.gpg" | sudo gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu ${CODENAME} main" | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt update && sudo apt install tailscale -y
sudo tailscale up
```

Authenticate in the URL or with your auth key. The machine will get a Tailscale IP (e.g. `100.x.x.x`).

**Other distros:** For Debian, RHEL, etc., see [Tailscale’s Linux install docs](https://tailscale.com/download/linux). Debian also uses codenames (e.g. `bookworm`, `bullseye`); use `lsb_release -cs` there too to get the codename first.

**If you still see a NO_PUBKEY error** after `sudo apt update`, the key or repo may be wrong. Remove the key, then re-add it using your **actual codename** from Step 1:

```bash
sudo rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg
# Replace 'noble' with your codename (e.g. jammy, focal) from Step 1
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.gpg | sudo gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu noble main" | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt update
```

Then run `sudo apt install tailscale -y` and `sudo tailscale up`.

**7.2 Confirm Tailscale and get the machine IP**

```bash
tailscale ip -4
tailscale status
```

**7.3 Test SSH over Tailscale (from your laptop/desktop on the same tailnet)**

```bash
ssh -p 2222 adminuser@100.x.x.x
```

Use the Tailscale IP from `tailscale ip -4`. Once this works, you can lock down public SSH (section 8).

**If you see “UDP GRO forwarding is suboptimally configured”** (e.g. on `enp0s1`), Tailscale is warning that UDP throughput can be improved. This matters most if the machine is an **exit node** or **subnet router** (section 9). Optional fix:

```bash
# Use the interface that has your default route (often enp0s1 on VPS)
NETDEV=$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")
sudo ethtool -K $NETDEV rx-udp-gro-forwarding on rx-gro-list off
```

Changes are lost after reboot. To make them persistent on systems using `networkd-dispatcher`:

```bash
printf '#!/bin/sh\n\nethtool -K %s rx-udp-gro-forwarding on rx-gro-list off\n' "$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")" | sudo tee /etc/networkd-dispatcher/routable.d/50-tailscale
sudo chmod 755 /etc/networkd-dispatcher/routable.d/50-tailscale
sudo /etc/networkd-dispatcher/routable.d/50-tailscale
```

Details: [Tailscale: UDP GRO config](https://tailscale.com/s/ethtool-config-udp-gro).

---

## 8. Disable SSH on the public internet (Tailscale-only SSH)

Only do this **after** you’ve confirmed you can SSH in via the Tailscale IP.

**8.1 Bind SSH to the Tailscale interface only**

Get the Tailscale IPv4:

```bash
tailscale ip -4
```

Edit SSH config:

```bash
sudo nano /etc/ssh/sshd_config
```

Ensure you have (replace `100.x.x.x` with the output of `tailscale ip -4`):

```
Port 2222
ListenAddress 100.x.x.x
```

`ListenAddress` makes SSH listen only on the Tailscale interface, so it’s unreachable on the public IP. If the Tailscale IP changes later (e.g. after re-auth), update this and restart SSH or you’ll lose access until you use the provider’s recovery console.

**8.2 Remove the SSH port from the firewall**

```bash
sudo ufw delete allow 2222/tcp
sudo ufw status
```

**8.3 Restart SSH**

```bash
# Debian/Ubuntu:
sudo systemctl restart ssh
# CentOS/RHEL/Alma/Rocky:
# sudo systemctl restart sshd
```

From now on, the only way in is via Tailscale: `ssh -p 2222 adminuser@100.x.x.x` (or `ssh adminuser@100.x.x.x` if you use port 22 on the Tailscale side). Public SSH is disabled; the box is fully hardened behind Tailscale.

---

## 9. Use the VPS as an exit node (“VPN” passthrough)

With the VPS as a **Tailscale exit node**, you can route your laptop/phone traffic through it. Your internet traffic goes: device → Tailscale → VPS → internet, so you appear with the VPS’s IP and location (handy for region-locked stuff or a bit of extra privacy on untrusted networks).

**9.1 Enable IP forwarding and allow Tailscale forwarding in UFW**

```bash
# Make IP forwarding persistent
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```

If you use UFW, allow forwarding on the Tailscale interface so exit-node traffic can pass through:

```bash
sudo ufw allow in on tailscale0
sudo ufw allow out on tailscale0
```

UFW often defaults to `DEFAULT_FORWARD_POLICY="DROP"`. If exit-node traffic doesn’t work, allow forwarding:

```bash
sudo nano /etc/default/ufw
# Set: DEFAULT_FORWARD_POLICY="ACCEPT"
sudo ufw reload
```

*(On this setup the only ingress is Tailscale, so accepting forward is acceptable.)*

**9.2 Advertise the node as an exit node**

If Tailscale is already up, re-run with the exit-node flag. If this is a fresh install, this is your first `tailscale up`:

```bash
sudo tailscale up --advertise-exit-node
```

**9.3 Approve the exit node in the Tailscale admin panel**

1. Open [admin.tailscale.com](https://admin.tailscale.com) and go to **Machines**.
2. Find this VPS and click it.
3. Under **Edit route settings**, enable **Use as exit node** and save.

**9.4 Use it from your devices**

- **Desktop/laptop:** Click the Tailscale icon → **Use exit node** → choose this VPS.
- **Phone (Tailscale app):** Settings → **Use exit node** → select this machine.

Your traffic will then go through the VPS. Turn off "Use exit node" when you don't need it.

---

## 10. OpenClaw (install and harden)

Get [OpenClaw](https://openclaw.ai) running first (install, run gateway, connect Telegram). Then harden with the steps below (security audit, tool policy, SOUL.md, file permissions). **Docker sandbox is optional** and more involved—skip it at first; you can add it later (10.7) if you want tool execution isolated in containers.

---

### 10.0 Install OpenClaw

**Prerequisites (Debian/Ubuntu):** Node.js 22+ and Git. Docker is only needed for the optional sandbox (10.7); omit it for a simple setup.

```bash
# Node.js 22 (NodeSource)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# Git
sudo apt install -y git
```

If the Node installer warns that the npm global bin dir is missing from PATH, add to `~/.bashrc` or `~/.zshrc`: `export PATH="$HOME/.npm-global/bin:$PATH"`, then open a new terminal.

**Install OpenClaw**

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

The installer detects Node.js, installs the OpenClaw CLI globally via npm, and may launch the onboarding wizard.

**Verify version (important)**

```bash
ssh -N -L 18789:127.0.0.1:18789 adminuser@100.83.6.5 -p 2222
openclaw --version
openclaw gateway install
openclaw dashboard --no-open
```

Use **2026.2.9 or higher**. If you see an older version (e.g. below 2026.1.29), update immediately because of known vulnerabilities:

```bash
openclaw update
```

**Check installation health**

```bash
openclaw doctor
```

Fix anything it reports before continuing. Then complete the onboarding wizard (`openclaw onboard` if it didn’t start): set gateway bind to `127.0.0.1`, set a strong gateway auth password, and configure your model provider(s) and channels (e.g. Telegram). After OpenClaw is working, proceed to the hardening steps below.

**Run the gateway (VPS/Linux)** — Over SSH, `openclaw gateway start` often fails (no D-Bus user session), so run the gateway in the foreground and use tmux so it survives disconnect:

```bash
sudo apt install -y tmux
tmux new -s openclaw
openclaw gateway run
# Detach: Ctrl+B then D. Reattach: tmux attach -t openclaw
```

Optional: to try background service instead, run `sudo loginctl enable-linger $USER`, set `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS` (see OpenClaw docs), then `openclaw gateway start`. If you see "Failed to connect to bus", use the tmux + `openclaw gateway run` flow above.

---

### 10.1 Security audit and auto-fix

Run the built-in audit and fix safe defaults:

```bash
openclaw security audit
```

Fix every finding (e.g. set gateway auth password, `dmPolicy`, bind to `127.0.0.1`). Then:

```bash
openclaw security audit --fix
openclaw security audit   # Should show no critical findings
```

---

### 10.2 Tool policy lockdown

Restrict which tools the agent can use (deny wins over allow):

```bash
openclaw config set tools.deny '["browser", "exec", "process", "apply_patch", "write", "edit"]'
```

Re-enable specific tools only when needed; remove from `deny` before adding to `allow`. Disable elevated (host) mode:

```bash
openclaw config set tools.elevated.enabled false
```

---

### 10.3 SOUL.md — agent identity and boundaries

Create `SOUL.md` in the agent workspace so every conversation gets clear boundaries (no financial actions, no following instructions from content, no shell/install without approval):

```bash
mkdir -p ~/.openclaw/workspace
# Edit ~/.openclaw/workspace/SOUL.md with Identity, Boundaries (financial/security/communication), and Capabilities
```

Include hard rules: no wallet/keys, no trades, no executing embedded instructions from emails/docs, no config or credential access. See [OpenClaw security docs](https://docs.openclaw.ai/gateway/security) and the full setup guide for a SOUL.md template.

---

### 10.4 File permissions for ~/.openclaw

Credentials and config are plaintext; restrict to owner only:

```bash
chmod 700 ~/.openclaw
chmod 600 ~/.openclaw/openclaw.json
chmod -R 700 ~/.openclaw/credentials/ 2>/dev/null
chmod -R 700 ~/.openclaw/agents/ 2>/dev/null
ls -la ~/.openclaw/   # Should show rwx------ / rw-------
```

---

### 10.5 Gateway and channel hardening (recap)

- Bind gateway to localhost only: `openclaw config set gateway.bind "127.0.0.1"`.
- Set a strong gateway auth password: `openclaw config set gateway.auth.password "YOUR_STRONG_PASSWORD"`.
- Telegram: `dmPolicy "pairing"`, `configWrites false`, `groupPolicy "disabled"`.

Access the Control UI over Tailscale (e.g. `http://100.x.x.x:18789/`) so the gateway is never exposed on the public internet.

**Control UI: "Disconnected (1008): device signature expired"** — Clear the site’s stored data in the browser (DevTools → Application → Local Storage), then reload. Approve the device again on the VPS: `openclaw devices list` then `openclaw devices approve <request-id>`. If the VPS clock is wrong, sync: `sudo timedatectl set-ntp true`.

---

### 10.7 Optional: Docker sandbox (add later)

Skip this at first. When you want tool execution isolated in containers, install Docker and enable the sandbox. The gateway process must have access to the Docker socket (user in `docker` group and gateway started from a session that has it—see below).

**Prerequisites:** Docker installed, user in `docker` group. After `sudo usermod -aG docker $USER`, log out of SSH and log back in so the new session has the group.

**10.7.1 Ensure Docker is running**

```bash
docker info
```

**10.7.2 Build the sandbox image**

```bash
openclaw sandbox recreate --all 2>/dev/null
# Or if needed:
OPENCLAW_DIR=$(npm root -g)/openclaw
$OPENCLAW_DIR/scripts/sandbox-setup.sh
```

**10.7.3 Enable sandboxing for all sessions**

```bash
openclaw config set agents.defaults.sandbox.mode "all"
openclaw config set agents.defaults.sandbox.scope "session"
openclaw config set agents.defaults.sandbox.workspaceAccess "ro"
```

- `mode: "all"` — every session runs in Docker.
- `scope: "session"` — one container per session.
- `workspaceAccess: "ro"` — agent can read workspace, not write from inside the sandbox.

**10.7.4 Network isolation for sandbox**

```bash
openclaw config set agents.defaults.sandbox.docker.network "none"
```

Sandbox containers get no internet; built-in web tools still run on the gateway.

**10.7.5 Resource limits**

```bash
openclaw config set agents.defaults.sandbox.docker.memory "512m"
openclaw config set agents.defaults.sandbox.docker.cpus 1
openclaw config set agents.defaults.sandbox.docker.pidsLimit 100
```

**10.7.6 Restart and verify**

```bash
openclaw gateway restart
openclaw sandbox explain
```

**"Permission denied" connecting to Docker socket** — If you see errors like:

```text
Failed to inspect sandbox image: permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock ... dial unix /var/run/docker.sock: connect: permission denied
```

the user running the OpenClaw gateway doesn’t have access to the Docker socket. The gateway process must run with your user in the `docker` group.

1. **Ensure your user is in `docker`:**
   ```bash
   groups
   # or
   id
   ```
   You should see `docker` in the list. If not: `sudo usermod -aG docker $USER`, then **log out and log back in** (or in the same shell run `newgrp docker`).

2. **Start the gateway in a session that has `docker`:** If you run the gateway in tmux, start it from a shell where `groups` already shows `docker` (e.g. after `newgrp docker` or a fresh SSH login). If the gateway was started by systemd user, that session may not have the docker group; use Option A (tmux + `openclaw gateway run`) from a shell where you’ve run `newgrp docker` so the process inherits the group.

3. **Restart the gateway** after fixing group membership (e.g. stop with Ctrl+C in tmux, run `newgrp docker` in that same tmux pane, then `openclaw gateway run` again).

---

### 10.8 Maintenance

- Run `openclaw security audit` regularly (e.g. weekly).
- Set API spending limits on Moonshot and Anthropic; monitor with `openclaw status --usage`.
- Rotate API keys, bot token, and gateway password periodically (e.g. every 3 months).

If you suspect compromise: `openclaw gateway stop`, revoke all credentials, inspect session logs under `~/.openclaw/agents/`, then rebuild and rotate everything.

