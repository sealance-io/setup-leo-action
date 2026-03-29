# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **security-hardened GitHub Action** for installing the [Leo](https://github.com/ProvableHQ/leo) compiler by building from source. It deliberately does not support pre-built binaries because ProvableHQ's releases lack cryptographic verification (no GPG signatures, Sigstore, or SLSA attestations).

## Architecture

**Composite Action** (`action.yml`) — a single-file GitHub Action written entirely in bash:
- Uses only `actions/cache` (SHA-pinned) as external dependency
- Inlines rustup instead of using third-party actions like `dtolnay/rust-toolchain`
- Two separate caches: binary cache (version+OS+arch) and cargo registry cache (version+rust+OS+arch)
- Flow: validate inputs → restore binary cache → (if miss) install Rust → restore cargo cache → clone Leo tag → optional cargo audit → build with `--locked` → install binary → save caches → cleanup

See `docs/ARCHITECTURE.md` for detailed design diagrams and rationale. See `docs/THREAT_MODEL.md` for security analysis and trust boundaries.

## Development Commands

### Local validation
```bash
# Validate action.yml syntax
python3 -c "import yaml; yaml.safe_load(open('action.yml'))"

# Lint shell scripts
shellcheck scripts/*.sh

# Run zizmor security analysis on workflows (version must match CI)
zizmor --min-severity medium .github/workflows/

# Verify a Leo release before updating (checks tag exists, Cargo.lock, runs audit)
./scripts/verify-release.sh 3.4.0
```

### SHA-pinning actions with pinact
The repo uses [pinact](https://github.com/suzuki-shunsuke/pinact) to manage SHA-pinned action references. Config is in `.pinact.yaml`. When adding or updating action references, run pinact to resolve version tags to commit SHAs.

### CI test matrix
The CI workflow (`.github/workflows/test.yml`) tests:
- Linux (ubuntu-24.04)
- macOS ARM64 (macos-14)
- macOS x86 (macos-15) — note: macos-15 runners are x86_64, not ARM
- Multiple Leo versions (3.1.0–3.4.0) each paired with their required Rust version from `rust-toolchain.toml`
- Cache restore behavior (runs after test-linux on non-PR events)
- Security analysis with [zizmor](https://docs.zizmor.sh)

CI runs on: push to main (tests + cache save), pull requests (tests only, cache-save=never), weekly Monday 6 AM UTC (keeps caches fresh).

The `lint` job runs zizmor security analysis on all workflow files. Findings at medium severity or above will fail the build. Use `# zizmor: ignore[rule-name]` comments to suppress false positives (see action.yml line 414 for an example).

### Dependabot
Dependabot checks for GitHub Actions updates daily (cron `0 9 * * *` UTC) with a 7-day cooldown on new versions. All action updates are grouped into a single PR. Commit prefix is `chore` with scope auto-added by Dependabot.

### Release workflow
The release workflow (`.github/workflows/release.yml`) automatically creates GitHub Releases when semver tags are pushed:
```bash
git tag -a v1.0.0 -m "Initial release"
git push origin v1.0.0
```

## Key Design Decisions

1. **Source-only builds**: `cargo build --release --locked` ensures reproducibility via Cargo.lock
2. **SHA-pinned dependencies**: All `actions/cache` uses are pinned by commit SHA, not version tags
3. **No third-party Rust actions**: rustup is inlined (~10 lines) to avoid dtolnay/rust-toolchain's force-push risk
4. **Separate cache invalidation**: Binary cache survives Rust updates; cargo cache includes rust-version in key
5. **`persist-credentials: false`**: All `actions/checkout` steps disable credential persistence

## Security Notes

- All external action SHAs must be verified before use
- The `--locked` flag is critical — never remove it from cargo build
- GPG/SLSA checks in verify-release.sh are informational only (ProvableHQ doesn't sign releases)
- When updating Leo versions, always run `./scripts/verify-release.sh <version>` first

## Adding New Leo Versions to CI

When a new Leo version is released, update `.github/workflows/test.yml`:

1. Check the required Rust version:
   ```bash
   curl -s "https://raw.githubusercontent.com/ProvableHQ/leo/v<VERSION>/rust-toolchain.toml"
   ```

2. Add to the `test-leo-versions` matrix in `test.yml`:
   ```yaml
   - leo: "<VERSION>"
     rust: "<RUST_VERSION>"  # from rust-toolchain.toml
   ```

3. Update `LEO_VERSION` env var at top of workflow if it should be the new default

## Local Testing with `act`

For testing the action locally using [nektos/act](https://github.com/nektos/act), see `docs/ACT_TESTING_GUIDE.md` for comprehensive setup instructions across platforms.

Quick start (requires Docker, Colima, or Podman):
```bash
# Create .actrc in project root
echo '-P ubuntu-24.04=catthehacker/ubuntu:act-22.04
-P ubuntu-latest=catthehacker/ubuntu:act-22.04
--container-architecture linux/arm64' > .actrc

# Run Linux test job
act push -j test-linux
```

**Limitations:** macOS/Windows runner jobs cannot be tested locally (act only supports Linux containers). The `actions/cache` uses a local cache server instead of GitHub's.
