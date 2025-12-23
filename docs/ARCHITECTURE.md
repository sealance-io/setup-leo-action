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
├── actions/cache/restore@SHA  (GitHub official)
├── actions/cache/save@SHA     (GitHub official)
│
└── External downloads:
    ├── https://sh.rustup.rs   (Official Rust project)
    └── github.com/ProvableHQ/leo (git clone)
```

### Why Not dtolnay/rust-toolchain?

From dtolnay's README:
> Any commit that is not within the history of master will eventually get
> garbage-collected and your workflows will fail.

This means:
- Pinning by SHA can break if dtolnay rebases master
- The 10 lines of bash we use instead are more stable

## Flow Diagram

```
┌─────────────────┐
│  Start Action   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ Validate Inputs │────▶│ Generate Cache  │
│ & Detect OS     │     │     Keys        │
└────────┬────────┘     └────────┬────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│ Restore Binary  │────▶│ Binary in Cache?│
│    Cache        │     └────────┬────────┘
└─────────────────┘              │
                          ┌──────┴──────┐
                          │             │
                         YES           NO
                          │             │
                          ▼             ▼
                   ┌──────────┐  ┌──────────────┐
                   │   Done   │  │ Install Rust │
                   └──────────┘  └──────┬───────┘
                                        │
                                        ▼
                                 ┌──────────────┐
                                 │ Restore Cargo│
                                 │    Cache     │
                                 └──────┬───────┘
                                        │
                                        ▼
                                 ┌──────────────┐
                                 │  Clone Leo   │
                                 │  (git tag)   │
                                 └──────┬───────┘
                                        │
                                        ▼
                                 ┌──────────────┐
                                 │ cargo audit  │
                                 │  (optional)  │
                                 └──────┬───────┘
                                        │
                                        ▼
                                 ┌──────────────┐
                                 │ cargo build  │
                                 │ --release    │
                                 │ --locked     │
                                 └──────┬───────┘
                                        │
                                        ▼
                                 ┌──────────────┐
                                 │   Install    │
                                 │   Binary     │
                                 └──────┬───────┘
                                        │
                                        ▼
                                 ┌──────────────┐
                                 │ Save Caches  │
                                 │ (conditional)│
                                 └──────┬───────┘
                                        │
                                        ▼
                                 ┌──────────────┐
                                 │   Cleanup    │
                                 └──────────────┘
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
| action.yml | ~400 | Main action logic |
| README.md | ~400 | Documentation |
| THREAT_MODEL.md | ~350 | Threat model |
| ARCHITECTURE.md | ~200 | This file |
| **Total** | **~1350** | Fully auditable |
