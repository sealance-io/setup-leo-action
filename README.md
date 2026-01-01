# setup-leo-action

A **security-hardened** GitHub Action for installing the [Leo](https://github.com/ProvableHQ/leo) programming language compiler by **building from source**.

## Why Source-Only?

This action deliberately **does not support pre-built binaries** because ProvableHQ's releases lack cryptographic verification. See [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) for the detailed threat model.

| Security Property | Pre-built Binary | Source Build (This Action) |
|-------------------|------------------|---------------------------|
| Code provenance | ❌ Trust release pipeline | ✅ Verified git tag |
| Dependency versions | ❌ Unknown | ✅ Locked via Cargo.lock |
| Tampering detection | ❌ SHA256 is self-attested | ✅ Reproducible from source |
| Vulnerability scanning | ❌ Not possible | ✅ cargo audit support |

**When ProvableHQ adopts release signing** (GPG, Sigstore, or SLSA attestations), this action can be extended to support verified binary downloads. Until then, source builds are the only secure option.

## Quick Start

```yaml
- uses: sealance-io/setup-leo-action@<SHA>
  with:
    version: '3.4.0'
```

That's it. The action handles Rust installation, caching, and building.

## Usage Examples

### Basic Usage

```yaml
name: CI
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-24.04  # Pin OS version for reproducibility
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
      
      - uses: sealance-io/setup-leo-action@<SHA>
        with:
          version: '3.4.0'
      
      - run: leo build
      - run: leo test
```

### Optimized Caching Strategy

GitHub Actions caches follow branch scoping rules:
- **Feature branches CAN access caches from the default branch**
- **Feature branches CANNOT access caches from sibling branches**
- **PR caches are isolated** to their merge ref

**Recommendation**: Run on push to `main` to warm caches for all feature branches:

```yaml
name: CI

on:
  push:
    branches: [main]  # Warm cache on main
  pull_request:

jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
      
      - uses: sealance-io/setup-leo-action@<SHA>
        with:
          version: '3.4.0'
          # Save cache only on main branch to avoid PR cache pollution
          cache-save: ${{ github.ref == 'refs/heads/main' && 'always' || 'never' }}
      
      - run: leo build
```

### With Security Audit

```yaml
- uses: sealance-io/setup-leo-action@<SHA>
  with:
    version: '3.4.0'
    run-audit: 'true'
    audit-deny-warnings: 'true'  # Fail on any vulnerability
```

### Multi-Platform Matrix

```yaml
jobs:
  build:
    strategy:
      matrix:
        include:
          - os: ubuntu-24.04
          - os: macos-14       # ARM64
          - os: macos-13       # x86_64
          - os: windows-2022
    
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
      
      - uses: sealance-io/setup-leo-action@<SHA>
        with:
          version: '3.4.0'
      
      - run: leo build
```

### Pinned Rust Version

```yaml
- uses: sealance-io/setup-leo-action@<SHA>
  with:
    version: '3.4.0'
    rust-version: '1.90.0'  # Pin specific Rust version
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `version` | **Yes** | - | Leo version without `v` prefix (e.g., `3.4.0`) |
| `rust-version` | No | `stable` | Rust toolchain version |
| `enable-cache` | No | `true` | Enable caching of Leo binary and cargo registry |
| `cache-save` | No | `on-success` | When to save cache: `always`, `on-success`, `never` |
| `run-audit` | No | `true` | Run cargo audit for vulnerability scanning |
| `audit-deny-warnings` | No | `false` | Fail build on audit warnings |
| `working-directory` | No | `${{ runner.temp }}` | Directory for build operations |

## Outputs

| Output | Description |
|--------|-------------|
| `leo-version` | Installed Leo version string |
| `cache-hit-binary` | Whether Leo binary was restored from cache |
| `cache-hit-cargo` | Whether cargo registry was restored from cache |
| `build-time-seconds` | Build duration (0 if cached) |

---

# Caching Architecture

This action uses **two separate caches** with different invalidation patterns:

## 1. Leo Binary Cache

```
Key: leo-binary-v{version}-{os}-{arch}
Example: leo-binary-v3.4.0-linux-x86_64
```

- **Contents**: The compiled `leo` binary only
- **Invalidation**: Only when Leo version changes
- **Size**: ~50-100 MB
- **Lifetime**: Stable across all builds of the same version

## 2. Cargo Registry Cache

```
Key: leo-cargo-v{version}-{rust-version}-{os}-{arch}
Example: leo-cargo-v3.4.0-stable-linux-x86_64
```

- **Contents**: `~/.cargo/registry/index/`, `~/.cargo/registry/cache/`, `~/.cargo/git/db/`
- **Invalidation**: When Leo version OR Rust version changes
- **Size**: ~200-500 MB
- **Lifetime**: Can be shared across Leo versions via restore-keys fallback

### What We DON'T Cache (and why)

| Directory | Why Not Cached |
|-----------|----------------|
| `~/.cargo/registry/src/` | Cargo recreates from compressed archives faster than cache restore |
| `target/` | Too large, changes frequently, not needed after install |
| `~/.cargo/bin/` (other tools) | Would cache unrelated tools, bloating cache |

## Cache Scoping Behavior

```
main branch
├── Creates: leo-binary-v3.4.0-linux-x86_64
├── Creates: leo-cargo-v3.4.0-stable-linux-x86_64
│
feature-branch (branched from main)
├── CAN restore: caches from main ✅
├── CANNOT restore: caches from other feature branches ❌
│
pull-request (targeting main)
├── CAN restore: caches from main ✅
├── CAN restore: caches from PR's own previous runs ✅
├── PR-created caches are isolated to that PR ⚠️
```

## Recommended Cache Strategy by Workflow Type

| Workflow | `cache-save` Setting | Rationale |
|----------|---------------------|-----------|
| Push to `main` | `always` | Warm cache for all branches |
| Pull requests | `never` | Avoid polluting 10GB cache quota |
| Scheduled builds | `always` | Keep caches fresh (7-day TTL) |
| Release builds | `on-success` | Only cache successful builds |

## Cache Limits

| Limit | Value |
|-------|-------|
| Total per repository | **10 GB** |
| Inactivity TTL | **7 days** |
| Eviction policy | LRU (least recently used) |

To avoid cache thrashing, consider:
1. Running weekly scheduled builds on `main` to refresh caches
2. Using `cache-save: never` on PRs
3. Cleaning up PR caches on close (see [examples/cleanup-workflow.yml](examples/cleanup-workflow.yml))

---

# Security Considerations

## Third-Party Action Dependencies

This action uses **only** GitHub's official `actions/cache` action, pinned by SHA:

```yaml
uses: actions/cache/restore@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0
uses: actions/cache/save@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0
```

### Why SHA Pinning Matters

In March 2025, the `tj-actions/changed-files` action was compromised. Attackers:
1. Gained repository access
2. Updated existing version tags (v35, v45) to point to malicious code
3. Exfiltrated CI secrets from **218+ repositories**

**Organizations using SHA-pinned actions were unaffected** because commit SHAs are immutable.

### Why We Don't Use These Actions

| Action | Reason Not Used |
|--------|----------------|
| `taiki-e/install-action` | Internal dependencies not SHA-pinned; checksums are maintainer-attested, not upstream-verified |
| `cargo-bins/cargo-binstall` | No signature verification by default; quickinstall backend is unaudited |
| `dtolnay/rust-toolchain` | Force-push risk on master branch (documented in their README) |
| `Swatinem/rust-cache` | Adds complexity; our use case is simpler (single binary) |
| `actions-rs/*` | Deprecated since Oct 2023; uses Node.js 12 (EOL) |

## Why We Build From Source

| Approach | Trust Requirements |
|----------|-------------------|
| **Pre-built binary** | Trust: ProvableHQ's build infrastructure, release signing (none exists), binary hosting |
| **cargo install from crates.io** | Trust: crates.io infrastructure, publisher credentials, version alignment with GitHub |
| **Source build (this action)** | Trust: GitHub (unavoidable), ProvableHQ's git repository |

Building from source with `--locked` ensures:
1. **Code provenance**: We verify the exact git tag
2. **Dependency pinning**: Cargo.lock specifies exact versions
3. **Auditability**: cargo audit can scan for known vulnerabilities
4. **Reproducibility**: Same inputs produce same outputs

## Future: When Will Binary Downloads Be Safe?

This action can support verified binary downloads when ProvableHQ implements **any** of:

- [ ] GPG-signed release tags
- [ ] Sigstore/cosign signatures on binaries
- [ ] SLSA provenance attestations (Level 2+)
- [ ] GitHub artifact attestations

See [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) for the complete threat model and verification criteria.

---

# Versioning and Pinning

## For Consumers

**Always pin by full commit SHA:**

```yaml
- uses: sealance-io/setup-leo-action@a1b2c3d4e5f6789...
```

**Do NOT use:**
```yaml
- uses: sealance-io/setup-leo-action@v1      # Tag can be moved
- uses: sealance-io/setup-leo-action@main    # Branch changes constantly
```

## For Action Maintainers

Use semantic versioning with immutable tags:

```
main          → Development (never pin to this)
v1            → Major version branch (updated for compatible changes)
v1.0.0        → Immutable release tag
v1.0.1        → Immutable patch release
```

Update `v1` branch (not tag) for non-breaking changes:
```bash
git checkout v1
git merge main
git push origin v1
git tag v1.0.1
git push origin v1.0.1
```

---

# Troubleshooting

## Build takes too long

First build compiles Leo from source (~5-15 minutes depending on runner). Subsequent builds restore from cache (~10-30 seconds).

**Solution**: Ensure caches are being saved on your default branch:
```yaml
cache-save: ${{ github.ref == 'refs/heads/main' && 'always' || 'never' }}
```

## Cache not being restored on feature branches

Feature branches can only access caches from:
1. The same branch
2. The default branch (usually `main`)

**Solution**: Push to `main` first to create the cache.

## "Tag mismatch" error

The git tag doesn't match the expected version.

**Solutions**:
1. Verify the version exists: `git ls-remote --tags https://github.com/ProvableHQ/leo | grep v3.4.0`
2. Check for typos in the version input

## cargo audit failures

Vulnerabilities were found in Leo's dependencies.

**Options**:
1. Set `audit-deny-warnings: false` to continue with warnings
2. Report vulnerabilities to ProvableHQ
3. Wait for upstream fix

## Windows-specific issues

Windows builds may have different behavior. Ensure:
1. Using `windows-2022` (or later) runners
2. Paths use forward slashes in YAML

---

# Contributing

1. Fork the repository
2. Make changes
3. Update SHA pins if changing action dependencies
4. Test with `act` or in a real workflow
5. Submit PR with security considerations documented

---

# License

This repository is licensed under the Apache License, Version 2.0.  
See the [LICENSE](./LICENSE) file for details.
