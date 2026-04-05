# AGENTS.md

Security-hardened GitHub Action that installs the [Leo](https://github.com/ProvableHQ/leo) compiler by building from source. Pre-built binaries are deliberately unsupported because ProvableHQ releases lack cryptographic verification (no GPG signatures, Sigstore, or SLSA attestations).

## File Map

| Path | Purpose |
|------|---------|
| `action.yml` | Composite action — all logic in bash |
| `scripts/verify-release.sh` | Verify a Leo release before updating |
| `.github/workflows/test.yml` | CI: multi-platform test matrix |
| `.github/workflows/release.yml` | Automated GitHub Releases on semver tags |
| `.pinact.yaml` | Config for SHA-pinning action references |
| `docs/ARCHITECTURE.md` | Design diagrams, caching strategy, rationale |
| `docs/THREAT_MODEL.md` | Trust boundaries, threat analysis (T1-T6) |
| `docs/ACT_TESTING_GUIDE.md` | Local testing with nektos/act |
| `docs/RELEASE.md` | Versioning, release process, Leo version updates |

## Architecture

Composite action (`action.yml`) using only `actions/cache` (SHA-pinned) as external dependency. Rustup is inlined (~10 lines) instead of third-party actions. Two separate caches: binary (version+OS+arch) and cargo registry (version+rust+OS+arch).

Flow: validate inputs > restore binary cache > (miss?) install Rust > restore cargo cache > clone Leo tag > optional cargo audit > `cargo build --release --locked` > install binary > save caches > cleanup.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed design and rationale.

## Development Commands

```bash
# Validate action.yml syntax
python3 -c "import yaml; yaml.safe_load(open('action.yml'))"

# Lint shell scripts
shellcheck scripts/*.sh

# Run zizmor security analysis (version must match CI)
zizmor --min-severity medium .github/workflows/

# Verify a Leo release before updating
./scripts/verify-release.sh <version>
```

SHA-pinning: use [pinact](https://github.com/suzuki-shunsuke/pinact) to resolve version tags to commit SHAs. Config in `.pinact.yaml`.

## CI

Test matrix in `.github/workflows/test.yml`:
- Platforms: ubuntu-24.04, macos-14 (ARM64), macos-15 (x86_64)
- Leo versions 3.1.0-4.0.0, each paired with required Rust from `rust-toolchain.toml`
- Triggers: push to main (tests + cache save), PRs (tests only, cache-save=never), weekly Monday 06:00 UTC
- Lint job: zizmor at medium severity; suppress false positives with `# zizmor: ignore[rule-name]`

Dependabot checks GitHub Actions daily (`0 9 * * *` UTC), 7-day cooldown, grouped into single PR.

## Invariants

These rules must never be violated:

- **`--locked` on cargo build** — ensures reproducibility via Cargo.lock; never remove
- **SHA-pin all external actions** — pin by commit SHA, not version tag; verify SHAs before use
- **`persist-credentials: false`** — on every `actions/checkout` step
- **Source-only builds** — no pre-built binaries until ProvableHQ adds cryptographic verification
- **Run `verify-release.sh`** — before adding any new Leo version

## Security

Builds from source with locked dependencies to eliminate binary supply-chain risk. All action references SHA-pinned. Minimal permissions model.

See [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) for trust boundaries, threat analysis, and criteria for future binary download support.

## Procedures

- **Adding Leo versions to CI**: [docs/RELEASE.md](docs/RELEASE.md#updating-leo-versions) (verify release, check Rust version, update test matrix)
- **Creating releases**: [docs/RELEASE.md](docs/RELEASE.md) (immutable semver tags, automated GitHub Releases)
- **Local testing with act**: [docs/ACT_TESTING_GUIDE.md](docs/ACT_TESTING_GUIDE.md) (Docker/Colima/Podman setup, Linux containers only)
