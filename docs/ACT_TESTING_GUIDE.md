# Comprehensive Guide: Testing GitHub Actions Locally with `act`

This guide covers setup, configuration, troubleshooting, and best practices for using [nektos/act](https://github.com/nektos/act) across different platforms.

> **Note:** `act` officially supports Docker only. Podman support is unofficial and may have limitations.

---

## Table of Contents

1. [Platform Setup](#platform-setup)
   - [macOS Apple Silicon + Docker Desktop](#macos-apple-silicon--docker-desktop)
   - [macOS Apple Silicon + Colima](#macos-apple-silicon--colima-docker-alternative)
   - [macOS Apple Silicon + Podman](#macos-apple-silicon--podman)
   - [Linux + Docker](#linux--docker)
   - [Linux + Podman](#linux--podman-rootless)
   - [Windows 11 + WSL2](#windows-11--wsl2)
2. [Configuration](#configuration)
3. [Platform Support Matrix](#platform-support-matrix)
4. [Common Issues & Solutions](#common-issues--solutions)
5. [Best Practices](#best-practices)
6. [Tips & Tricks](#tips--tricks)

---

## Platform Setup

### macOS Apple Silicon + Docker Desktop

**Recommended for:** Easiest setup, best compatibility

#### Installation

```bash
# Install Docker Desktop
brew install --cask docker

# Install act
brew install act

# Optional: Install Rosetta 2 for x86 emulation
softwareupdate --install-rosetta
```

#### Configuration

Create `~/.actrc`:
```
-P ubuntu-24.04=catthehacker/ubuntu:act-22.04
-P ubuntu-22.04=catthehacker/ubuntu:act-22.04
-P ubuntu-latest=catthehacker/ubuntu:act-22.04
--container-architecture linux/arm64
```

#### First Run

```bash
# Start Docker Desktop first, then:
act --list                    # List available workflows
act push                      # Run push event
act -j job-name              # Run specific job
```

#### Known Issues

| Issue | Solution |
|-------|----------|
| "arch arm64 not found" for tools | Use `--container-architecture linux/amd64` (slower, uses emulation) |
| Image pull failures | Ensure Docker Desktop is running and has network access |

---

### macOS Apple Silicon + Colima (Docker Alternative)

**Recommended for:** Lighter resource usage, no Docker Desktop license concerns

#### Installation

```bash
# Install Colima and Docker CLI
brew install colima docker

# Install act
brew install act
```

#### Start Colima (optimized for Apple Silicon)

```bash
# Recommended configuration
colima start \
  --vm-type vz \
  --vz-rosetta \
  --cpu 4 \
  --memory 8 \
  --arch aarch64

# Verify
docker info
```

#### Configuration

Same as Docker Desktop - create `~/.actrc`:
```
-P ubuntu-24.04=catthehacker/ubuntu:act-22.04
-P ubuntu-22.04=catthehacker/ubuntu:act-22.04
-P ubuntu-latest=catthehacker/ubuntu:act-22.04
--container-architecture linux/arm64
```

#### Usage

```bash
# Ensure Colima is running
colima status || colima start

# Run act
act push -j test-linux
```

#### Advantages over Docker Desktop

- ~80% faster I/O performance
- Lower CPU/memory usage
- No licensing restrictions
- Uses Apple's Virtualization Framework with Rosetta 2

---

### macOS Apple Silicon + Podman

**Recommended for:** When Docker/Colima aren't options; requires more setup

> ⚠️ **Podman support is unofficial.** Expect some limitations.

#### Installation

```bash
# Install Podman
brew install podman

# Initialize and start machine
podman machine init
podman machine start

# Install act
brew install act
```

#### Setup Options

**Option A: With Admin Access (Recommended)**

```bash
# Install the mac-helper (requires sudo)
sudo /opt/homebrew/Cellar/podman/$(podman --version | cut -d' ' -f3)/bin/podman-mac-helper install

# Restart podman machine
podman machine stop && podman machine start

# Now act works without extra config
act push
```

**Option B: Without Admin Access**

```bash
# Get socket path
export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"

# Run act with socket mounting disabled
act --container-daemon-socket - push -j test-linux
```

#### Configuration for Non-Admin Users

Add to `~/.zshrc`:
```bash
# Podman socket for act/docker compatibility
export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"
```

Create `.actrc` in project:
```
-P ubuntu-24.04=catthehacker/ubuntu:act-22.04
-P ubuntu-latest=catthehacker/ubuntu:act-22.04
--container-architecture linux/arm64
--container-daemon-socket -
```

#### Known Issues & Workarounds

| Issue | Cause | Solution |
|-------|-------|----------|
| `mkdir .../podman.sock: operation not supported` | Socket bind mount fails | Use `--container-daemon-socket -` |
| Permission denied on socket | Missing mac-helper | Use `DOCKER_HOST` + `--container-daemon-socket -` |
| Volume mount errors | Podman VM limitations | Consider switching to Colima/Docker |

---

### Linux + Docker

**Recommended for:** Native performance, full compatibility

#### Installation

```bash
# Install Docker Engine (Debian/Ubuntu)
curl -fsSL https://get.docker.com | sh

# Add user to docker group (logout/login required)
sudo usermod -aG docker $USER

# Install act
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

#### Configuration

Create `~/.actrc`:
```
-P ubuntu-24.04=catthehacker/ubuntu:act-22.04
-P ubuntu-22.04=catthehacker/ubuntu:act-22.04
-P ubuntu-latest=catthehacker/ubuntu:act-22.04
```

#### Usage

```bash
act push
act -j test-linux -v  # Verbose output
```

---

### Linux + Podman (Rootless)

**Recommended for:** Security-conscious environments, no root daemon

#### Installation

```bash
# Install Podman (Fedora)
sudo dnf install podman

# Install Podman (Debian/Ubuntu)
sudo apt install podman

# Install act
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

#### Enable Podman Socket

```bash
# Enable user socket (rootless)
systemctl --user enable --now podman.socket

# Enable lingering (keeps socket alive after logout)
loginctl enable-linger $USER

# Set DOCKER_HOST
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
```

Add to `~/.bashrc`:
```bash
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
```

#### Configuration

Create `~/.actrc`:
```
-P ubuntu-24.04=catthehacker/ubuntu:act-22.04
-P ubuntu-latest=catthehacker/ubuntu:act-22.04
```

#### Known Limitations

- Ports below 1024 require extra configuration
- Some systemd-dependent actions won't work
- cgroups v2 recommended for full functionality

---

### Windows 11 + WSL2

**Recommended for:** Windows development with Linux containers

#### Prerequisites

- Windows 11 (22631+) or Windows 10 (19041+)
- WSL2 enabled with a Linux distribution
- Hardware virtualization enabled in BIOS

#### Option A: Docker Desktop + WSL2 Backend

```powershell
# Install Docker Desktop via winget
winget install Docker.DockerDesktop

# Install act
winget install nektos.act
```

Configure Docker Desktop:
1. Settings → Resources → WSL Integration
2. Enable integration with your WSL distro
3. Apply & Restart

#### Option B: Docker Engine in WSL2 (No Docker Desktop)

```bash
# Inside WSL2 (Ubuntu)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install act
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

#### Critical: File Location for Performance

| Location | Performance | Recommendation |
|----------|-------------|----------------|
| `/home/user/project` (WSL filesystem) | ✅ Fast | **Use this** |
| `/mnt/c/Users/...` (Windows filesystem) | ❌ Slow | Avoid |

```bash
# Clone repos to WSL filesystem, not /mnt/c
cd ~
git clone https://github.com/your/repo
cd repo
act push
```

#### Known Issues

| Issue | Solution |
|-------|----------|
| Empty volumes | Store project in WSL filesystem, not `/mnt/c/` |
| Inconsistent file access | Use `--bind` flag or copy mode |
| Permission errors | Run `sudo usermod -aG docker $USER` and re-login |

---

## Configuration

### Configuration Files

| File | Location | Purpose |
|------|----------|---------|
| `~/.actrc` | Home directory | Global defaults |
| `.actrc` | Project root | Project-specific settings |
| `.env` | Project root | Environment variables |
| `.secrets` | Project root | Secrets (gitignore this!) |
| `.vars` | Project root | Repository variables |
| `event.json` | Project root | Custom event payload |

### Example `.actrc`

```
# Runner image mappings
-P ubuntu-24.04=catthehacker/ubuntu:act-22.04
-P ubuntu-22.04=catthehacker/ubuntu:act-22.04
-P ubuntu-latest=catthehacker/ubuntu:act-22.04

# Architecture (for Apple Silicon)
--container-architecture linux/arm64

# Cache configuration
--cache-server-path ~/.cache/act-cache

# Artifact server
--artifact-server-path ./artifacts
```

### Secrets and Variables

```bash
# Pass secrets
act -s MY_SECRET=value
act -s GITHUB_TOKEN="$(gh auth token)"
act --secret-file .secrets

# Pass variables
act --var MY_VAR=value
act --var-file .vars

# Pass inputs (workflow_dispatch)
act workflow_dispatch --input name=value
```

### `.secrets` File Format

```bash
# .secrets (add to .gitignore!)
GITHUB_TOKEN=ghp_xxxxxxxxxxxx
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
```

---

## Platform Support Matrix

| Feature | Docker (macOS) | Colima (macOS) | Podman (macOS) | Docker (Linux) | Podman (Linux) | WSL2 |
|---------|---------------|----------------|----------------|----------------|----------------|------|
| **Official Support** | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| **Setup Complexity** | Easy | Easy | Hard | Easy | Medium | Medium |
| **Linux Workflows** | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ |
| **macOS Workflows** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Windows Workflows** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **actions/cache** | ⚠️ Local | ⚠️ Local | ⚠️ Local | ⚠️ Local | ⚠️ Local | ⚠️ Local |
| **ARM64 Native** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **x86 Emulation** | ✅ Rosetta | ✅ Rosetta | ⚠️ QEMU | ⚠️ QEMU | ⚠️ QEMU | N/A |
| **Resource Usage** | High | Low | Medium | Low | Low | Medium |

**Legend:** ✅ Full support | ⚠️ Partial/workarounds needed | ❌ Not supported

---

## Common Issues & Solutions

### Container/Image Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `No such image: ghcr.io/catthehacker/ubuntu:act-latest` | Image pull failed | Run `docker pull ghcr.io/catthehacker/ubuntu:act-22.04` manually |
| `invalid reference format` | Malformed image name | Check `.actrc` for typos |
| `Cannot connect to Docker daemon` | Docker not running | Start Docker/Colima/Podman |
| `arch arm64 not found` | Tool not available for ARM | Use `--container-architecture linux/amd64` |

### Volume/Mount Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `operation not supported` (macOS/Podman) | Socket mount fails | Use `--container-daemon-socket -` |
| `error while creating mount source path` | Path translation issue | Check file exists, use absolute paths |
| Empty volumes (Windows) | Cross-filesystem access | Move project to WSL filesystem |

### Cache/Artifact Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `ACTIONS_RUNTIME_TOKEN` error | Artifact server not started | Add `--artifact-server-path ./artifacts` |
| `internal error in cache backend` | No local cache server | Use `--cache-server-path ~/.cache/act` or skip with `if: ${{ !env.ACT }}` |

### Permission Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `permission denied` on socket | User not in docker group | `sudo usermod -aG docker $USER` + re-login |
| `permission denied` (Podman macOS) | Missing mac-helper | Use `DOCKER_HOST` env var approach |

---

## Best Practices

### 1. Skip Problematic Steps Locally

```yaml
steps:
  # Skip cache in act (uses local cache server instead)
  - uses: actions/cache@v4
    if: ${{ !env.ACT }}
    with:
      path: ~/.cache
      key: ${{ runner.os }}-cache

  # Alternative: Always runs but may use local cache
  - uses: actions/cache@v4
    with:
      path: ~/.cache
      key: ${{ runner.os }}-cache
```

### 2. Skip Jobs Locally

```yaml
jobs:
  deploy:
    # Skip deployment when testing locally
    if: ${{ !github.event.act }}
    runs-on: ubuntu-latest
```

Run with: `act -e event.json` where `event.json` contains `{"act": true}`

### 3. Create a Local Test Workflow

```yaml
# .github/workflows/local-test.yml (add to .gitignore)
name: Local Test
on: workflow_dispatch

jobs:
  test:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - uses: ./
        with:
          version: '3.4.0'
          enable-cache: 'false'  # Disable for faster iteration
```

```bash
act workflow_dispatch -j test
```

### 4. Use Offline Mode After First Run

```bash
# First run: pulls images and actions
act push

# Subsequent runs: use cached
act --action-offline-mode --pull=false push
```

### 5. Validate Before Running

```bash
# Dry run (no containers created)
act -n push

# List workflows
act -l

# Validate workflow syntax
act --validate
```

---

## Tips & Tricks

### Speed Up Iteration

```bash
# Run single job
act -j test-linux

# Reuse containers between runs
act --reuse push

# Skip image pulls
act --pull=false push

# Combine for fastest iteration
act --reuse --pull=false --action-offline-mode -j test-linux
```

### Debug Workflows

```bash
# Verbose output
act -v push

# Very verbose
act -v -v push

# See container logs
act --verbose push 2>&1 | tee act.log
```

### Use GitHub Token

```bash
# With GitHub CLI installed
act -s GITHUB_TOKEN="$(gh auth token)" push

# Or set in .secrets file
echo "GITHUB_TOKEN=$(gh auth token)" >> .secrets
act --secret-file .secrets push
```

### Matrix Subset

```bash
# Run only specific matrix combination
act --matrix os:ubuntu-22.04 push
act --matrix node:18 push
```

### Custom Event Payload

```json
// event.json
{
  "act": true,
  "pull_request": {
    "head": {
      "ref": "feature-branch"
    }
  }
}
```

```bash
act pull_request -e event.json
```

### Wrapper Script

Create `~/bin/act-local`:
```bash
#!/bin/bash
# Wrapper for act with common settings

# For Podman on macOS (non-admin)
if command -v podman &>/dev/null && [[ "$(uname)" == "Darwin" ]]; then
    export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"
    EXTRA_ARGS="--container-daemon-socket -"
fi

exec act \
    --cache-server-path "${HOME}/.cache/act-cache" \
    --artifact-server-path "./artifacts" \
    ${EXTRA_ARGS} \
    "$@"
```

---

## What Cannot Be Tested Locally

| Feature | Reason | Workaround |
|---------|--------|------------|
| macOS runners | act only supports Linux containers | Use `-P macos-latest=-self-hosted` (runs on host, loses isolation) |
| Windows runners | act only supports Linux containers | Use `-P windows-latest=-self-hosted` |
| GitHub-hosted secrets | Not accessible locally | Use `.secrets` file |
| GitHub API rate limits | Different context | Use `GITHUB_TOKEN` |
| Exact GitHub environment | Minor differences exist | Final testing on GitHub |
| `actions/cache` with GitHub backend | Needs GitHub infrastructure | Use local cache server or skip |
| Cross-workflow artifact sharing | Limited support | Test in GitHub |
| OIDC tokens | GitHub-specific | Mock or skip |

---

## Quick Reference

```bash
# Basic usage
act                              # Run default (push) event
act pull_request                 # Run pull_request event
act -j job-name                  # Run specific job
act -l                           # List workflows

# Configuration
act -s SECRET=value              # Pass secret
act --secret-file .secrets       # Load secrets from file
act -e event.json                # Custom event payload
act --input key=value            # workflow_dispatch input

# Performance
act --reuse                      # Keep containers
act --pull=false                 # Don't pull images
act --action-offline-mode        # Use cached actions

# Debugging
act -n                           # Dry run
act -v                           # Verbose
act --validate                   # Validate only

# Platform
act --container-architecture linux/amd64   # Force x86
act -P ubuntu-latest=image:tag             # Custom image
```

---

## References

- [nektos/act Repository](https://github.com/nektos/act)
- [act Documentation](https://nektosact.com/)
- [act Runners Guide](https://nektosact.com/usage/runners.html)
- [catthehacker/docker_images](https://github.com/catthehacker/docker_images)
- [Podman on macOS](https://podman-desktop.io/docs/migrating-from-docker/managing-docker-compatibility)
- [Colima](https://github.com/abiosoft/colima)
- [Docker Desktop WSL2](https://docs.docker.com/desktop/features/wsl/)
