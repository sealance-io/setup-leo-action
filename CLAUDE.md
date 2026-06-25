# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Security-hardened GitHub composite action that installs the [Leo](https://github.com/ProvableHQ/leo) compiler by building from source. Pre-built binaries are deliberately unsupported because ProvableHQ releases lack cryptographic verification (no GPG, Sigstore, or SLSA attestations).

## Architecture

Single composite action (`action.yml`) — all logic is inline bash, no JavaScript/TypeScript. The shipped action only depends on `actions/cache` (SHA-pinned); CI workflows additionally use pinned lint tooling. Rustup is inlined (~10 lines) instead of using third-party setup actions.

**Flow** (step numbers match `# STEP N:` headers in `action.yml`):
validate inputs → restore binary cache → (cache miss?) install Rust → restore cargo cache → resolve and clone Leo git tag → optional cargo audit → `cargo build --release --locked` → install binary → save caches → cleanup build dir

**Two separate caches** with different invalidation patterns:
- **Binary cache**: `leo-binary-v{version}-{os}-{arch}` — only invalidates on Leo version change
- **Cargo registry cache**: `leo-cargo-v{version}-{rust}-{os}-{arch}` — invalidates on Leo or Rust version change, with restore-keys fallback

**Leo 4.x layout detection**: Leo 4.x moved the binary to `crates/leo/Cargo.toml`. The clone step auto-detects this and passes `-p <package>` to cargo build. Leo 3.x builds from the workspace root.

## Development Commands

```bash
# Validate action.yml syntax
python3 -c "import yaml; yaml.safe_load(open('action.yml'))"

# Lint shell scripts
find scripts -name '*.sh' -type f -exec shellcheck {} +

# Validate workflows and local action metadata
actionlint

# Run zizmor security analysis (version must match CI)
zizmor --min-severity medium .github/workflows/

# Verify a Leo release before adding support
./scripts/verify-release.sh <version>
```

SHA-pinning: use [pinact](https://github.com/suzuki-shunsuke/pinact) to resolve version tags to commit SHAs. Config in `.pinact.yaml`.

## CI

Test workflow (`.github/workflows/test.yml`):
- **Platforms**: ubuntu-24.04, macos-14 (ARM64), macos-15 (x86_64)
- **Leo version matrix**: 3.4.0–4.3.0, each paired with required Rust from upstream `rust-toolchain.toml`
- **Triggers**: push to main (tests + cache save), PRs (tests only, `cache-save=never`), weekly Monday 06:00 UTC
- **Lint job**: shellcheck, YAML validation, actionlint, and zizmor at medium severity; suppress false positives with `# zizmor: ignore[rule-name]`
- **Smoke tests**: `leo new` + `leo build` + `leo test`; Leo 4.x also tests `leo new --library`

Dependabot checks GitHub Actions daily, 7-day cooldown, grouped into single PR.

## Invariants

These rules must never be violated:

- **`--locked` on cargo build** — ensures reproducibility via Cargo.lock; never remove
- **SHA-pin all external actions** — pin by commit SHA, not version tag; verify SHAs before use
- **`persist-credentials: false`** — on every `actions/checkout` step
- **Source-only builds** — no pre-built binaries until ProvableHQ adds cryptographic verification
- **Run `verify-release.sh`** — before adding any new Leo version

## Adding a New Leo Version

1. `./scripts/verify-release.sh <version>` — checks tag, Cargo.lock, build layout, audit
2. Check required Rust using the source tag reported by `verify-release.sh` (`leo-lang-v<VERSION>` for modern releases, `v<VERSION>` for older releases)
3. Update `.github/workflows/test.yml`: add to `test-leo-versions` matrix, update `LEO_VERSION` env if new default, update smoke tests if CLI changed
4. Create a patch release documenting support

## Key Files

| Path | Purpose |
|------|---------|
| `action.yml` | Composite action — all build logic in bash |
| `scripts/verify-release.sh` | Verify a Leo release before updating |
| `.github/workflows/test.yml` | CI: multi-platform test matrix |
| `.github/workflows/release.yml` | Automated GitHub Releases on semver tags |
| `docs/THREAT_MODEL.md` | Trust boundaries and threat analysis |
| `docs/ARCHITECTURE.md` | Design diagrams, caching strategy, rationale |
| `docs/RELEASE.md` | Versioning and release process |
