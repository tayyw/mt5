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

Use a **custom SSH port** from the start (e.g. `2222`). Pick one and use it consistently below.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp
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

**4.4 Test login as the new user on the custom port (new terminal; keep current session open)**

```bash
ssh -p 2222 adminuser@your-server-ip
sudo whoami   # should print: root
```

If that works, use `adminuser` from here on.

---

## 5. Harden SSH (port, no root, keys only)

Only do this **after** key-based login works for `adminuser` on port 2222.

```bash
sudo nano /etc/ssh/sshd_config
```

Set or add (use the same port as in UFW). Comment out or replace any existing `Port` / `PermitRootLogin` / etc.:

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
sudo systemctl restart ssh
# CentOS/RHEL/Alma/Rocky:
# sudo systemctl restart sshd
```

Test again in a new terminal: `ssh -p 2222 adminuser@your-server-ip`. Do **not** close your current session until that works.

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

```bash
# Debian/Ubuntu (see https://tailscale.com/download/linux for other distros)
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt update && sudo apt install tailscale -y
sudo tailscale up
```

Authenticate in the URL or with your auth key. The machine will get a Tailscale IP (e.g. `100.x.x.x`).

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

## 10. OpenClaw hardening (if running OpenClaw on this VPS)

If you run [OpenClaw](https://openclaw.ai) on this machine, apply these steps **after** OpenClaw is installed and working. They reduce risk from malicious skills, prompt injection, credential theft, and runaway automation.

**Threats this mitigates:** Malicious ClawHub skills (e.g. credential harvesters), prompt injection via messages, runaway API loops, memory poisoning, and plaintext credentials under `~/.openclaw/`.

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

### 10.2 Docker sandbox (tool execution isolation)

Run the agent's tool execution (shell, file ops) inside Docker so a compromised or tricked agent can't touch the host.

**10.2.1 Ensure Docker is running**

```bash
docker info
```

**10.2.2 Build the sandbox image**

```bash
openclaw sandbox recreate --all 2>/dev/null
# Or if needed:
OPENCLAW_DIR=$(npm root -g)/openclaw
$OPENCLAW_DIR/scripts/sandbox-setup.sh
```

**10.2.3 Enable sandboxing for all sessions**

```bash
openclaw config set agents.defaults.sandbox.mode "all"
openclaw config set agents.defaults.sandbox.scope "session"
openclaw config set agents.defaults.sandbox.workspaceAccess "ro"
```

- `mode: "all"` — every session runs in Docker.
- `scope: "session"` — one container per session.
- `workspaceAccess: "ro"` — agent can read workspace, not write from inside the sandbox.

**10.2.4 Network isolation for sandbox**

```bash
openclaw config set agents.defaults.sandbox.docker.network "none"
```

Sandbox containers get no internet; built-in web tools still run on the gateway.

**10.2.5 Resource limits**

```bash
openclaw config set agents.defaults.sandbox.docker.memory "512m"
openclaw config set agents.defaults.sandbox.docker.cpus 1
openclaw config set agents.defaults.sandbox.docker.pidsLimit 100
```

**10.2.6 Restart and verify**

```bash
openclaw gateway restart
openclaw sandbox explain
```

---

### 10.3 Tool policy lockdown

Restrict which tools the agent can use (deny wins over allow):

```bash
openclaw config set tools.deny '["browser", "exec", "process", "apply_patch", "write", "edit"]'
```

Re-enable specific tools only when needed; remove from `deny` before adding to `allow`. Disable elevated (host) mode:

```bash
openclaw config set tools.elevated.enabled false
```

---

### 10.4 SOUL.md — agent identity and boundaries

Create `SOUL.md` in the agent workspace so every conversation gets clear boundaries (no financial actions, no following instructions from content, no shell/install without approval):

```bash
mkdir -p ~/.openclaw/workspace
# Edit ~/.openclaw/workspace/SOUL.md with Identity, Boundaries (financial/security/communication), and Capabilities
```

Include hard rules: no wallet/keys, no trades, no executing embedded instructions from emails/docs, no config or credential access. See [OpenClaw security docs](https://docs.openclaw.ai/gateway/security) and the full setup guide for a SOUL.md template.

---

### 10.5 File permissions for ~/.openclaw

Credentials and config are plaintext; restrict to owner only:

```bash
chmod 700 ~/.openclaw
chmod 600 ~/.openclaw/openclaw.json
chmod -R 700 ~/.openclaw/credentials/ 2>/dev/null
chmod -R 700 ~/.openclaw/agents/ 2>/dev/null
ls -la ~/.openclaw/   # Should show rwx------ / rw-------
```

---

### 10.6 Gateway and channel hardening (recap)

- Bind gateway to localhost only: `openclaw config set gateway.bind "127.0.0.1"`.
- Set a strong gateway auth password: `openclaw config set gateway.auth.password "YOUR_STRONG_PASSWORD"`.
- Telegram: `dmPolicy "pairing"`, `configWrites false`, `groupPolicy "disabled"`.

Access the Control UI over Tailscale (e.g. `http://100.x.x.x:18789/`) so the gateway is never exposed on the public internet.

---

### 10.7 Maintenance

- Run `openclaw security audit` regularly (e.g. weekly).
- Set API spending limits on Moonshot and Anthropic; monitor with `openclaw status --usage`.
- Rotate API keys, bot token, and gateway password periodically (e.g. every 3 months).

If you suspect compromise: `openclaw gateway stop`, revoke all credentials, inspect session logs under `~/.openclaw/agents/`, then rebuild and rotate everything.

Your traffic will then go through the VPS. Turn off “Use exit node” when you don’t need it.
