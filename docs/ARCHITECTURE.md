# Architecture

This document explains the design decisions and architecture of setup-leo-action.

## Design Principles

1. **Security First**: Every decision prioritizes security over convenience
2. **Minimal Trust Surface**: Use as few external dependencies as possible
3. **Transparency**: All code is auditable bash, no compiled binaries
4. **Future-Proof**: Designed to support verified binaries when available

## Why a Composite Action?

We evaluated three options for packaging this as a reusable component:

| Approach | Pros | Cons |
|----------|------|------|
| **Composite Action** | Same job context, PATH works, simple invocation | Cannot define multiple jobs |
| **Reusable Workflow** | Multi-job support, permissions control | Isolated context, tool not available to caller |
| **JavaScript Action** | Full Node.js ecosystem, complex logic | Requires build step, larger attack surface |

**Decision: Composite Action** because:
- Leo must be available in the caller's subsequent steps (reusable workflow fails this)
- Pure bash is auditable without build artifacts
- No npm dependencies to audit

## Why Source-Only Build?

See [THREAT_MODEL.md](THREAT_MODEL.md) for the full threat model. Summary:

| Pre-built Binary | Source Build |
|------------------|--------------|
| Trust release pipeline | Trust git repository |
| Opaque dependencies | Cargo.lock pins versions |
| Cannot audit | Can run cargo audit |
| Self-attested checksums | Git commit = provenance |

## Caching Strategy

### Two Separate Caches

We maintain two caches with different invalidation patterns:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Leo Binary Cache                             │
│  Key: leo-binary-v{version}-{os}-{arch}                         │
│  Contents: /usr/local/bin/leo                                   │
│  Invalidates: Only on Leo version change                        │
│  Size: ~50-100 MB                                               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   Cargo Registry Cache                           │
│  Key: leo-cargo-v{version}-{rust-version}-{os}-{arch}           │
│  Contents: ~/.cargo/registry/index, cache, git/db               │
│  Invalidates: Leo version OR Rust version change                │
│  Size: ~200-500 MB                                              │
└─────────────────────────────────────────────────────────────────┘
```

### Cargo Cache Restore-Keys Fallback

The cargo registry cache uses a 3-tier restore-keys cascade for partial matches:

```
leo-cargo-v{version}-{rust-version}-{os}-        # same version+rust, any arch
leo-cargo-v{version}-{rust-version}-              # same version+rust
leo-cargo-v{version}-                             # same Leo version only
```

This allows new Rust versions or platforms to warm-start from a related cache rather than starting cold.

### Why Not Cache target/?

The `target/` directory:
- Is very large (1-5 GB)
- Changes frequently
- Is not needed after binary is installed
- Would bloat cache quota

### Why Not Use Swatinem/rust-cache?

We considered `Swatinem/rust-cache` but decided against it:

1. **Trust surface**: Adds another third-party action to audit
2. **Complexity**: We only need to cache the registry, not build artifacts
3. **Control**: We want explicit control over cache keys for Leo-specific versioning

## Action Dependencies

```
setup-leo-action
│
├── actions/cache/restore@668228...  (GitHub official, v5.0.4)
├── actions/cache/save@668228...     (GitHub official, v5.0.4)
│
└── External downloads:
    ├── https://sh.rustup.rs   (Official Rust project)
    └── github.com/ProvableHQ/leo (git clone)
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `version` | Yes | — | Leo version (e.g., `3.4.0`) |
| `rust-version` | No | `stable` | Rust toolchain version |
| `enable-cache` | No | `true` | Enable binary + cargo caching |
| `cache-save` | No | `on-success` | When to save: `always`, `on-success`, `never` |
| `run-audit` | No | `true` | Run cargo audit for vulnerabilities |
| `audit-deny-warnings` | No | `false` | Fail on audit warnings (not just errors) |
| `working-directory` | No | `$RUNNER_TEMP/leo-build` | Directory to clone and build Leo |

## Outputs

| Output | Description |
|--------|-------------|
| `leo-version` | Installed Leo version string |
| `cache-hit-binary` | Whether binary was restored from cache |
| `cache-hit-cargo` | Whether cargo registry was restored from cache |
| `build-time-seconds` | Build duration (0 if cached) |

### Why Not dtolnay/rust-toolchain?

From dtolnay's README:
> Any commit that is not within the history of master will eventually get
> garbage-collected and your workflows will fail.

This means:
- Pinning by SHA can break if dtolnay rebases master
- The 10 lines of bash we use instead are more stable

## Flow Diagram

Step numbers below match the `# STEP N:` headers in `action.yml`:

```
┌──────────────────────────────┐
│ Step 1: Validate Inputs &    │
│   Configure Environment      │
│   (version, OS, cache keys)  │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Step 2: Restore Binary Cache │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Check if Leo Already         │
│ Available (version match?)   │
│ (unnumbered; between 2 & 3)  │
└──────────────┬───────────────┘
               │
        ┌──────┴──────┐
     skip=true     skip=false
        │              │
        │              ▼
        │   ┌──────────────────────────────┐
        │   │ Step 3: Install Rust         │
        │   │   Toolchain (rustup.rs)      │
        │   └──────────────┬───────────────┘
        │                  │
        │                  ▼
        │   ┌──────────────────────────────┐
        │   │ Step 4: Restore Cargo        │
        │   │   Registry Cache             │
        │   │   (with restore-keys)        │
        │   └──────────────┬───────────────┘
        │                  │
        │                  ▼
        │   ┌──────────────────────────────┐
        │   │ Step 5: Clone Leo (git tag)  │
        │   │   + GPG check (informational)│
        │   └──────────────┬───────────────┘
        │                  │
        │                  ▼
        │   ┌──────────────────────────────┐
        │   │ Step 6: cargo audit          │
        │   │   (optional, default on)     │
        │   └──────────────┬───────────────┘
        │                  │
        │                  ▼
        │   ┌──────────────────────────────┐
        │   │ Step 7: cargo build --release│
        │   │   --locked + Install Binary  │
        │   └──────────────┬───────────────┘
        │                  │
        ├──────────────────┘
        │
        ▼
┌──────────────────────────────┐
│ Step 8: Verify Installation  │
│   (version check, PATH)      │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Step 9: Save Caches          │
│   (conditional on input &    │
│    cache-hit status)         │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Step 10: Cleanup Build Dir   │
└──────────────────────────────┘
```

## Future: Binary Download Support

When ProvableHQ adds cryptographic verification, the flow will become:

```
┌─────────────────┐
│  Start Action   │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ Check for Binary with Valid Signature   │
│ (Sigstore/SLSA/GPG)                     │
└────────┬───────────────────┬────────────┘
         │                   │
      VERIFIED            UNVERIFIED
         │                   │
         ▼                   ▼
┌─────────────────┐  ┌─────────────────┐
│ Download Binary │  │ Build from      │
│ & Verify Sig    │  │ Source          │
└────────┬────────┘  └────────┬────────┘
         │                    │
         └──────────┬─────────┘
                    │
                    ▼
            ┌──────────────┐
            │    Done      │
            └──────────────┘
```

The `inputs` would expand to include:
- `prefer-binary: true/false`
- `require-signature: true/false`
- `allowed-signers: [list]`

## Line Count

Keeping the action small and auditable:

| File | Lines | Purpose |
|------|-------|---------|
| action.yml | ~580 | Main action logic (bash + YAML) |
| README.md | ~380 | User documentation |
| THREAT_MODEL.md | ~340 | Security analysis |
| ARCHITECTURE.md | ~260 | This file |
| RELEASE.md | ~120 | Release process |
| ACT_TESTING_GUIDE.md | ~685 | Local testing guide |
| **Total** | **~2365** | Fully auditable |
