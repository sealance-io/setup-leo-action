# AGENTS.md

Security-hardened GitHub Action that installs the [Leo](https://github.com/ProvableHQ/leo) compiler by building from source. Pre-built binaries are deliberately unsupported because ProvableHQ releases lack cryptographic verification (no GPG signatures, Sigstore, or SLSA attestations).

## Architecture

Composite action (`action.yml`) — all logic is inline bash, no JavaScript/TypeScript — using only `actions/cache` (SHA-pinned) as external dependency. CI workflows additionally use pinned lint tooling. Rustup is inlined (~10 lines) instead of third-party setup actions.

Two separate caches with different invalidation patterns:
- Binary cache: `leo-binary-v{version}-{os}-{arch}` — only invalidates on Leo version change
- Cargo registry cache: `leo-cargo-v{version}-{rust}-{os}-{arch}` — invalidates on Leo or Rust version change, with restore-keys fallback

Leo 4.x layout detection: Leo 4.x moved the binary to `crates/leo/Cargo.toml`. The clone step auto-detects this and passes `-p <package>` to cargo build. Leo 3.x builds from the workspace root.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed design and rationale.

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

# Verify a Leo release before updating
./scripts/verify-release.sh <version>
```

SHA-pinning: use [pinact](https://github.com/suzuki-shunsuke/pinact) to resolve version tags to commit SHAs. Config in `.pinact.yaml`.

## CI

- Lint job: shellcheck, YAML validation, actionlint, and zizmor at medium severity; suppress false positives with `# zizmor: ignore[rule-name]`

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

## Adding a New Leo Version

1. `./scripts/verify-release.sh <version>` — checks tag, Cargo.lock, build layout, audit
2. Check required Rust using the source tag reported by `verify-release.sh` (`leo-lang-v<VERSION>` for modern releases, `v<VERSION>` for older releases)
3. Update `.github/workflows/test.yml`: add to `test-leo-versions` matrix, update `LEO_VERSION` env if new default, update smoke tests if CLI changed
4. Create a patch release documenting support

## Procedures

- **Adding Leo versions to CI**: [docs/RELEASE.md](docs/RELEASE.md#updating-leo-versions) (verify release, check Rust version, update test matrix)
- **Creating releases**: [docs/RELEASE.md](docs/RELEASE.md) (immutable semver tags, automated GitHub Releases)
- **Local testing with act**: [docs/ACT_TESTING_GUIDE.md](docs/ACT_TESTING_GUIDE.md) (Docker/Colima/Podman setup, Linux containers only)
