# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **security-hardened GitHub Action** for installing the [Leo](https://github.com/ProvableHQ/leo) compiler by building from source. It deliberately does not support pre-built binaries because ProvableHQ's releases lack cryptographic verification (no GPG signatures, Sigstore, or SLSA attestations).

## Architecture

**Composite Action** (`action.yml`) - A single-file GitHub Action written entirely in bash (~580 lines):
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

# Verify a Leo release before updating (checks tag exists, Cargo.lock, runs audit)
./scripts/verify-release.sh 3.4.0
```

### CI test matrix
The CI workflow (`.github/workflows/test.yml`) tests:
- Linux (ubuntu-24.04)
- macOS ARM64 (macos-14)
- macOS x86 (macos-13)
- Multiple Rust versions (stable, 1.90.0, 1.88.0)
- Cache restore behavior
- Security analysis with [zizmor](https://docs.zizmor.sh)

CI runs on: push to main (tests + cache save), pull requests (tests only), weekly schedule (keeps caches fresh).

The `lint` job runs [zizmor](https://docs.zizmor.sh) security analysis on all workflow files. Findings at medium severity or above will fail the build. Use `# zizmor: ignore[rule-name]` comments to suppress false positives (see action.yml line 414 for an example).

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

## Security Notes

- All external action SHAs must be verified before use
- The `--locked` flag is critical - never remove it from cargo build
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

## File Structure

- `action.yml` - Main action logic (composite action with bash steps)
- `scripts/verify-release.sh` - Pre-update verification script
- `examples/` - Sample workflow configurations for users
- `docs/ACT_TESTING_GUIDE.md` - Comprehensive guide for local testing with act
- `docs/THREAT_MODEL.md` - Security analysis and trust assumptions
- `docs/ARCHITECTURE.md` - Design decisions and flow diagrams
- `docs/RELEASE.md` - Release process and versioning strategy
- `.github/workflows/test.yml` - CI workflow (tests + lint + zizmor)
- `.github/workflows/release.yml` - Automated release on tag push
- `.github/dependabot.yml` - Weekly updates for GitHub Actions dependencies
- `.github/CODEOWNERS` - Maintainer assignments for PR reviews
