# CLAUDE.md

Read [AGENTS.md](AGENTS.md) for full project context, file map, architecture, dev commands, CI details, and procedures.

## Invariants

These rules must never be violated:

- **`--locked` on cargo build** — ensures reproducibility via Cargo.lock; never remove
- **SHA-pin all external actions** — pin by commit SHA, not version tag; verify SHAs before use
- **`persist-credentials: false`** — on every `actions/checkout` step
- **Source-only builds** — no pre-built binaries until ProvableHQ adds cryptographic verification
- **Run `verify-release.sh`** — before adding any new Leo version

## Development Commands

```bash
python3 -c "import yaml; yaml.safe_load(open('action.yml'))"
shellcheck scripts/*.sh
zizmor --min-severity medium .github/workflows/
./scripts/verify-release.sh <version>
```

SHA-pinning: use [pinact](https://github.com/suzuki-shunsuke/pinact) to resolve version tags to commit SHAs. Config in `.pinact.yaml`.
