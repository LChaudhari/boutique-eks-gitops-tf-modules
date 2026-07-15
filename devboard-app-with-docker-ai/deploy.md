# Deploy Notes — Modern Docker Tools

A plain-English guide to four newer Docker features and how they fit a project
like DevBoard (React frontend + Go backend + Postgres). Each section answers
three questions: **what is it**, **why do you care**, and **a simple example**.

> Looking for just the commands? See [`README-Docker-AI.md`](./README-Docker-AI.md).

| Tool                     | One-line purpose                              |
| ------------------------ | --------------------------------------------- |
| Docker Scout             | Finds & fixes vulnerabilities in your image   |
| Docker Model Runner      | Run AI models locally with `docker` commands  |
| Docker Hardened Images   | Minimal base images = smaller attack surface  |
| Ask Gordon               | Built-in AI assistant for Docker & your project |

---

## 1. Docker Scout — "a health checkup for your image"

**What it is:** A tool that scans your Docker image and reports which packages
inside it have known security holes — called **CVEs** (Common Vulnerabilities
and Exposures) — and how to fix them.

**Why you care:** Your image isn't just your code. It also bundles a base OS,
libraries, and a language runtime. Any of those can have a known bug an attacker
could exploit. Scout reads everything inside the image and checks it against a
public database of known vulnerabilities.

**Analogy:** Like scanning the ingredients label on food for anything that's
been recalled.

**Example:**

```bash
# Build the backend image
docker build -t devboard-backend ./backend

# Quick summary of vulnerabilities
docker scout quickview devboard-backend

# Full list of CVEs
docker scout cves devboard-backend

# Suggestions on how to fix them (e.g. a better base image)
docker scout recommendations devboard-backend
```

Example output (simplified):

```text
Your image uses golang:1.23  →  12 vulnerabilities (2 high)
Recommendation: switch base to golang:1.23-alpine  →  0 high
```

You then change one line in your `Dockerfile` (the base image) and rebuild.

---

## 2. Docker Model Runner — "run AI models like you run containers"

**What it is:** A way to download and run AI/LLM models locally using the same
`docker` command you already know. The model runs on your machine and exposes a
local API endpoint, so your app can talk to it with no cloud account.

**Why you care:** You can add AI features (chat, summaries, search) to an app
without sending data to an external service or paying per request — great for
prototyping and learning.

**Analogy:** Like `docker run`, but instead of starting a database, you start a
chatbot.

**Example:**

```bash
# Pull a model (like pulling an image)
docker model pull ai/smollm2

# List the models you have
docker model list

# Chat with it
docker model run ai/smollm2 "Summarize what a Kanban board is in one line."
```

**How DevBoard *could* use it:** the backend calls the local model endpoint to
auto-summarize a task's description or suggest a priority — all running on your
laptop, no API key needed.

---

## 3. Docker Hardened Images — "a base image with less to break"

**What it is:** Minimal, security-focused base images. They strip out everything
not strictly needed to run your app — no shell, no package manager, no extra
tools — so there's far less that can be attacked or contain vulnerabilities.

**Why you care:** A smaller image means a **smaller attack surface**. If there's
no shell inside the container, an attacker who breaks in has almost nothing to
work with. These images are also smaller and start faster.

**Analogy:** Shipping a parcel with only the item inside — no extra padding, no
tools an intruder could misuse.

**Example (Go backend):**

A normal Dockerfile ends with a full OS:

```dockerfile
FROM golang:1.23           # ~800MB, includes a shell, apt, etc.
# ...build steps...
CMD ["./server"]
```

A hardened version uses a tiny base for the final stage:

```dockerfile
# Stage 1 — build
FROM golang:1.23 AS build
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o server .

# Stage 2 — run on a hardened, minimal base (no shell, no package manager)
FROM gcr.io/distroless/static     # or a Docker Hardened Image (dhi.io/...)
COPY --from=build /app/server /server
USER nonroot
CMD ["/server"]
```

**Result:** an image that's a few MB, has no shell to exploit, and ships only
your compiled binary.

---

## 4. Ask Gordon — "an AI assistant built into Docker"

**What it is:** Docker's built-in AI helper (in Docker Desktop and the CLI). You
ask it questions about Docker and your own project in plain English, and it
answers using the context of your files, images, and containers.

**Why you care:** Instead of searching docs or guessing flags, you just ask. It
can read your `Dockerfile` or `docker-compose.yml` and give specific advice for
*your* project.

**Analogy:** A Docker expert sitting next to you who can also see your screen.

**Example:**

```bash
# A general question
docker ai "How do I reduce the size of my Go image?"

# A question about your actual project (it can read your files)
docker ai "What's wrong with my docker-compose.yml?"
docker ai "Explain what my backend Dockerfile does"
```

In Docker Desktop, "Ask Gordon" appears as a chat panel. Example exchange:

```text
You:     Why is my backend container restarting?
Gordon:  Your backend depends on postgres but tries to connect before the DB
         is ready. Add a healthcheck + a depends_on condition...
```

---

## In short

Scout keeps images **safe**, Hardened Images keep them **small and safe**,
Model Runner lets you **add local AI**, and Ask Gordon **helps you do all of it**
by answering questions about your own project.
