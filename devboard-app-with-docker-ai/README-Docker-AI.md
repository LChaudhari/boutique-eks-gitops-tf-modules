# Docker Setup & Tools — Hands-On Cheat Sheet

A practical, copy-paste reference for getting Docker Desktop running on Ubuntu
and using four modern Docker tools with this project:

1. **Docker Scout** — scan images for security vulnerabilities (CVEs)
2. **Docker Model Runner (DMR)** — run AI/LLM models locally
3. **Docker Hardened Images (DHI)** — minimal, secure base images
4. **Ask Gordon** — Docker's built-in AI assistant

> For *what each tool is and why it matters*, see [`deploy.md`](./deploy.md).
> This file is just the commands.

---

## 1. Install Docker Desktop on Ubuntu

### Step 1 — Check that virtualization (KVM) works

Docker Desktop runs a small Linux VM, so your CPU must support KVM.

```bash
sudo apt install cpu-checker
kvm-ok                        # should print: "KVM acceleration can be used"
sudo usermod -aG kvm $USER    # give your user access (log out/in after)
```

### Step 2 — Add Docker's apt repository

This is needed so the installer can pull in Docker's dependencies.

```bash
# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to apt's sources
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

### Step 3 — Download and install Docker Desktop

Grab the latest `.deb` from
[docs.docker.com/desktop/setup/install/linux/ubuntu](https://docs.docker.com/desktop/setup/install/linux/ubuntu/):

```bash
wget https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb
sudo apt update
sudo apt install ./docker-desktop-amd64.deb
```

> You can safely ignore the *"Download is performed unsandboxed as root"*
> warning at the end of the install.

### Step 4 — Launch and verify

```bash
systemctl --user start docker-desktop
docker version       # both Client and Server should report a version
```

---

## 2. Docker Scout — find vulnerabilities (CVEs)

Scout scans an image and lists known security issues in its packages.
You must be logged in first.

```bash
# One-time install (Docker Desktop already includes Scout)
# curl -fsSL https://raw.githubusercontent.com/docker/scout-cli/main/install.sh | sh

docker login                                              # required

docker scout quickview  myapp:latest                      # quick CVE + base-image summary
docker scout cves       myapp:latest                      # full list of CVEs
docker scout cves       --only-severity critical,high myapp:latest
docker scout recommendations myapp:latest                 # suggested base-image upgrades
docker scout compare    myapp:v2 --to myapp:v1            # diff CVEs between two tags
docker scout sbom       --format spdx -o sbom.json myapp:latest
docker scout policy     myapp:latest --exit-code         # CI gate (non-zero on policy fail)
```

### Try it on this project's frontend

```bash
# Build the frontend image first
cd frontend
docker build -t devboard-fe:full .

# Scan it (local:// means "an image on my machine", not from a registry)
docker scout quickview local://devboard-fe:full          # summary of vulnerabilities
docker scout cves      local://devboard-fe:full          # full CVE list
```

To reduce those vulnerabilities, switch to a **Docker Hardened Image** (see §4).

---

## 3. Docker Model Runner (DMR) — run AI models locally

Pull and run LLMs with the same `docker` workflow you already know. The model
runs on your machine and exposes a local API — no cloud account or API key.

```bash
docker model status                  # is the model runner enabled?
docker model pull ai/smollm2         # download a model (e.g. ai/smollm2, ai/gemma3)
docker model list                    # list downloaded models
docker model ps                      # show currently running models
docker model run ai/smollm2          # start an interactive chat (REPL)
docker model logs                    # view model runner logs
```

Run a one-off prompt instead of the interactive REPL:

```bash
docker model run ai/gemma3 "Summarize what a Kanban board is in one line."
```

> **Heads up:** the model is `ai/gemma3` (Google **Gemma**), not "gamma".

---

## 4. Docker Hardened Images (DHI) — minimal, secure base images

DHI base images strip out the shell, package manager, and extra tools — far less
for an attacker to use, and smaller/faster too. They live in the `dhi.io`
registry and require access (a Docker subscription).

```bash
docker login dhi.io
docker pull dhi.io/library/python:3.13
docker run --rm dhi.io/library/python:3.13 -c "print('hi')"
```

Use a hardened image in your `Dockerfile` — typically a full image to build,
then a hardened one to run:

```dockerfile
# Build stage — full image (has the toolchain to compile/bundle)
FROM dhi.io/node:24-dev AS build
# ...build steps...

# Run stage — hardened image (no shell, no package manager)
FROM dhi.io/node:24
# ...copy the build output...
```

---

## 5. Ask Gordon — Docker's built-in AI assistant

Ask questions about Docker and *your own project* in plain English. Gordon can
read your `Dockerfile` and `docker-compose.yml` to give specific answers.

```bash
docker ai                                              # start an interactive session

docker ai "How do I reduce the size of my Go image?"   # general question
docker ai "What's wrong with my docker-compose.yml?"   # about your project
docker ai "Explain what my backend Dockerfile does"
```

In Docker Desktop, "Ask Gordon" also appears as a chat panel.

---

## Quick reference

| Tool                   | Key command                          | Purpose                                |
| ---------------------- | ------------------------------------ | -------------------------------------- |
| Docker Scout           | `docker scout cves <image>`          | Find vulnerabilities (CVEs) in images  |
| Docker Model Runner    | `docker model run <model>`           | Run AI/LLM models locally              |
| Docker Hardened Images | `FROM dhi.io/...`                    | Minimal, secure base images            |
| Ask Gordon             | `docker ai "<question>"`             | AI assistant for Docker & your project |
