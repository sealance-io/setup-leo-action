# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **security-hardened GitHub Action** for installing the [Leo](https://github.com/ProvableHQ/leo) compiler by building from source. It deliberately does not support pre-built binaries because ProvableHQ's releases lack cryptographic verification (no GPG signatures, Sigstore, or SLSA attestations).

## Architecture

**Composite Action** (`action.yml`) - A single-file GitHub Action written entirely in bash:
- Uses only `actions/cache` (SHA-pinned) as external dependency
- Inlines rustup instead of using third-party actions like `dtolnay/rust-toolchain`
- Two separate caches: binary cache (version+OS+arch) and cargo registry cache (version+rust+OS+arch)
- Flow: validate inputs → restore binary cache → (if miss) install Rust → restore cargo cache → clone Leo tag → optional cargo audit → build with `--locked` → install binary → save caches → cleanup

## Development Commands

### Testing the action locally
```bash
# Validate action.yml syntax
python3 -c "import yaml; yaml.safe_load(open('action.yml'))"

# Lint shell scripts
shellcheck scripts/*.sh

# Verify a Leo release before updating
./scripts/verify-release.sh 3.4.0
```

### CI runs automatically on
- Push to main (tests + cache save)
- Pull requests (tests only, no cache save)
- Weekly schedule (keeps caches fresh)

## Key Design Decisions

1. **Source-only builds**: `cargo build --release --locked` ensures reproducibility via Cargo.lock
2. **SHA-pinned dependencies**: All `actions/cache` uses are pinned by commit SHA, not version tags
3. **No third-party Rust actions**: rustup is inlined (~10 lines) to avoid dtolnay/rust-toolchain's force-push risk
4. **Separate cache invalidation**: Binary cache survives Rust updates; cargo cache includes rust-version in key

## Security Notes

- All external action SHAs must be verified before use
- The `--locked` flag is critical - never remove it from cargo build
- GPG/SLSA checks in verify-release.sh are informational only (ProvableHQ doesn't sign releases)
