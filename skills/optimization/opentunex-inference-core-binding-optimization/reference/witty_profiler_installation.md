---
name: witty_profiler_installation
description: Core-only installation guide for Witty Profiler (no HTTP server). Use when witty-profiler is not available on the client.
---

# Installation Guide (Core Only — No HTTP Server)

This guide installs Witty Profiler with **core dependencies only**. The HTTP server (FastAPI/uvicorn) is intentionally **not** installed — Witty Profiler runs in **offline mode**, which is the mode used by this skill (`witty-profiler --offline ...`).

Source: [openeuler/witty-profiler](https://gitcode.com/openeuler/witty-profiler) — `collector/python/docs/getting-started/installation.md`.

---

## System Requirements

### Operating System
- **Linux**: Primary supported platform
  - Ubuntu 20.04+ or equivalent
  - Kernel 4.18+ (5.x+ recommended for eBPF support)

### Python Version
- **Python 3.11** or higher (required)
- Python 3.12 supported
- Earlier versions not supported due to type hint requirements

### Hardware
- **CPU**: x86_64 or ARM64 (aarch64)
- **Memory**: 512MB minimum, 2GB+ recommended for large topologies
- **Disk**: 100MB for installation, additional space for logs/data

---

## Installation Methods

### Method 1: Using uv (Recommended)

[uv](https://github.com/astral-sh/uv) is a fast Python package manager that simplifies dependency management.

```bash
# Install uv if not already installed
curl -LsSf https://astral.sh/uv/install.sh | sh

# Clone Witty Profiler repository
git clone https://gitcode.com/openeuler/witty-profiler.git
cd witty-profiler

# Create virtual environment with Python 3.11
uv venv .venv --python 3.11

# Activate virtual environment
source .venv/bin/activate

# Install core dependencies
uv sync
```

> **Important**: Do NOT run `uv sync --group server` — that pulls in HTTP server (FastAPI/uvicorn) dependencies, which are not required for offline topology collection.

### Method 2: Using pip

```bash
# Clone repository
git clone https://gitcode.com/openeuler/witty-profiler.git
cd witty-profiler

# Create virtual environment
python3.11 -m venv .venv
source .venv/bin/activate

# Install in development mode (core only)
pip install -e .
```

> **Important**: Do NOT install the `server` extra (`pip install -e ".[server]"`) — it is not needed for offline mode.

### Method 3: From PyPI (when available)

```bash
# Core installation only
pip install witty-profiler
```

> **Important**: Do NOT install `witty-profiler[server]` — the server extra is not required for offline mode.

---

## Optional Components

### eBPF Tools (C++ Binaries)

The socket collector requires a compiled binary for kernel-level instrumentation:

```bash
# Install build dependencies (Ubuntu/Debian)
sudo apt-get install build-essential cmake libbpf-dev clang llvm bpftool pkg-config libelf-dev zlib1g-dev

# Build all eBPF tools (socket/cache/sched)
witty-profiler-build
# or
python -m witty_profiler.tools.build

# Binaries created under: src/witty_profiler/binary/
```

**Alternative**: Use pre-built binaries from releases (coming soon).

---

## Verifying Installation

### Check Python API

```bash
python -c "from witty_profiler.controller.witty_profiler_core import WittyProfilerCore; print('✓ Core imported')"
python -c "from witty_profiler.graph.graph import Graph; print('✓ Graph imported')"
python -c "from witty_profiler.collector.local_collector import get_local_collectors; print('✓ Collectors imported')"
```

### Check CLI

```bash
# Show help
python -m witty_profiler --help

# Expected output:
# usage: witty-profiler [-h] [--config CONFIG] [--verify] [--host HOST] [--port PORT]
#               [--offline] [--duration DURATION] [--log-level LOG_LEVEL]
#               [--dump-config DUMP_CONFIG] [--view-graph] [--pid PID]
# ...
```

### Confirm Offline Mode Works

Without server extras installed, Witty Profiler runs in offline mode only — which is the intended mode for this skill. Verify by running a short offline collection:

```bash
python -m witty_profiler --offline --duration 5
```

---

## Troubleshooting

### Python Version Issues

**Error**: `SyntaxError` or `TypeError` during import

**Solution**: Verify Python version:

```bash
python --version  # Must be 3.11+
```

Recreate virtual environment with correct Python:

```bash
uv venv .venv --python 3.11
```

### Build Failures

**Error**: `CMake not found` or `libbpf-dev not installed`

**Solution**: Install build dependencies:

```bash
# Ubuntu/Debian
sudo apt-get install build-essential cmake libbpf-dev

# RHEL/CentOS
sudo yum install gcc-c++ cmake libbpf-devel

# Arch Linux
sudo pacman -S base-devel cmake libbpf
```

### Permission Issues

**Error**: `Permission denied` when running collectors

**Solution**: Some collectors require elevated privileges:

```bash
# Run with sudo (for kernel instrumentation)
sudo python -m witty_profiler

# Or add CAP_NET_ADMIN capability
sudo setcap cap_net_admin+ep .venv/bin/python
```

---

## Platform-Specific Notes

### Ubuntu/Debian

```bash
# Install all dependencies
sudo apt-get update
sudo apt-get install python3.11 python3.11-venv build-essential cmake libbpf-dev

# Enable eBPF (if kernel < 5.0)
sudo modprobe bpf
```

### RHEL/CentOS

```bash
# Enable EPEL repository
sudo yum install epel-release

# Install dependencies
sudo yum install python311 gcc-c++ cmake libbpf-devel
```

### Arch Linux

```bash
# All dependencies available in official repos
sudo pacman -S python python-pip base-devel cmake libbpf
```
