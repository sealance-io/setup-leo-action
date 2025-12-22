# Threat Model

This document describes the security properties, trust assumptions, and design decisions for the setup-leo-action.

## Executive Summary

This action **builds Leo from source** rather than downloading pre-built binaries because ProvableHQ's release infrastructure lacks cryptographic verification. This document explains that decision, defines the trust model, and specifies the criteria for enabling binary downloads in the future.

## Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GitHub Actions Runner                                │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         Your Workflow                                  │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    setup-leo-action                              │  │  │
│  │  │                                                                  │  │  │
│  │  │   ┌──────────────────┐    ┌────────────────────────────────┐   │  │  │
│  │  │   │  actions/cache   │    │  Source Build Pipeline         │   │  │  │
│  │  │   │  (SHA-pinned)    │    │                                │   │  │  │
│  │  │   └────────┬─────────┘    │  ┌──────────┐  ┌───────────┐  │   │  │  │
│  │  │            │              │  │  git     │  │  cargo    │  │   │  │  │
│  │  │            │              │  │  clone   │  │  build    │  │   │  │  │
│  │  │            │              │  └────┬─────┘  └─────┬─────┘  │   │  │  │
│  │  │            │              │       │              │        │   │  │  │
│  │  └────────────┼──────────────┴───────┼──────────────┼────────┘   │  │  │
│  │               │                      │              │            │  │  │
│  └───────────────┼──────────────────────┼──────────────┼────────────┘  │  │
│                  │                      │              │               │  │
└──────────────────┼──────────────────────┼──────────────┼───────────────┘  │
                   │                      │              │                  │
      ┌────────────▼───────────┐   ┌──────▼──────┐  ┌────▼─────┐           │
      │  GitHub Cache Service  │   │  github.com │  │ crates.io│           │
      │  (GitHub-operated)     │   │  /Provable  │  │ (deps)   │           │
      └────────────────────────┘   │  HQ/leo     │  └──────────┘           │
                                   └─────────────┘                         │
```

## Trust Assumptions

### Required Trust (Unavoidable)

| Entity | What We Trust | Risk if Compromised |
|--------|---------------|---------------------|
| GitHub Actions infrastructure | Runner integrity, job isolation, secrets protection | Complete workflow compromise |
| GitHub.com repository hosting | ProvableHQ/leo repository integrity | Malicious source served |
| GitHub Cache Service | Cache integrity, isolation between repos | Cache poisoning (limited blast radius) |

### Conditional Trust

| Entity | When Trusted | What We Trust |
|--------|--------------|---------------|
| rustup.rs | Always (for Rust install) | Rust toolchain authenticity |
| crates.io | During cargo build | Leo's transitive dependencies (via Cargo.lock) |
| RustSec Advisory DB | If audit enabled | Vulnerability data accuracy |

### Explicitly NOT Trusted

| Entity | Why Not Trusted |
|--------|-----------------|
| ProvableHQ binary releases | No cryptographic signatures, self-attested checksums |
| taiki-e/install-action | Checksums are maintainer-attested, not upstream-verified |
| cargo-binstall | No signature verification, unaudited quickinstall backend |
| actions-rs/* | Deprecated, uses EOL Node.js 12 runtime |

## Why We Don't Trust Pre-Built Binaries

### Current State of ProvableHQ Releases

As of December 2025, ProvableHQ's Leo releases have:

| Security Property | Status | Implication |
|-------------------|--------|-------------|
| GPG-signed tags | ❌ Absent | Cannot verify tag author |
| GPG-signed commits | ❌ Absent | Cannot verify commit author |
| Sigstore/cosign signatures | ❌ Absent | Cannot verify binary provenance |
| SLSA attestations | ❌ Absent | Cannot verify build process |
| GitHub artifact attestations | ❌ Absent | Cannot verify GitHub built it |
| Reproducible builds | ❌ Not verified | Cannot independently verify binary matches source |
| SHA256 checksums | ✅ Present | **Self-attested** - useless if release pipeline compromised |

### The Self-Attestation Problem

ProvableHQ publishes SHA256 checksums alongside their binaries:

```
e3e54f7166bb5e...  leo-v3.4.0-x86_64-unknown-linux-gnu.zip
```

This checksum **provides no security** against a compromised release pipeline because:

1. Attacker compromises ProvableHQ's release infrastructure
2. Attacker builds malicious binary
3. Attacker computes SHA256 of malicious binary
4. Attacker publishes malicious binary **with correct checksum**
5. All verification passes, malicious code executes

Self-attested checksums only protect against:
- Accidental corruption during download
- CDN serving wrong file

They do **not** protect against:
- Compromised build/release infrastructure
- Compromised maintainer credentials
- Supply chain attacks

### Why Source Builds Are More Secure

Building from source with `cargo build --locked`:

| Property | Binary Download | Source Build |
|----------|-----------------|--------------|
| Code inspection | ❌ Impossible | ✅ Full source available |
| Dependency versions | ❌ Unknown | ✅ Pinned in Cargo.lock |
| Vulnerability scanning | ❌ Cannot scan binary | ✅ cargo audit works |
| Provenance | ❌ Trust release pipeline | ✅ Git tag = specific commit |
| Reproducibility | ❌ Cannot verify | ✅ Same inputs = same output |

## Threat Analysis

### T1: Compromised ProvableHQ Repository

**Threat**: Attacker gains write access to ProvableHQ/leo and pushes malicious code.

**Likelihood**: Low (requires GitHub account compromise or insider threat)

**Impact**: Critical (malicious code compiled and executed)

**Mitigations**:
- Shallow clone of specific tag (limits exposure window)
- cargo audit detects known vulnerabilities
- Git history is auditable
- Building from tag (not branch) limits movable target attacks

**Residual Risk**: If attacker force-pushes a tag, we would build malicious code. Mitigated by the fact that force-pushing tags is unusual and would likely be detected.

### T2: Compromised Transitive Dependencies

**Threat**: One of Leo's dependencies on crates.io is compromised.

**Likelihood**: Medium (supply chain attacks are increasing)

**Impact**: High (malicious code included in build)

**Mitigations**:
- `--locked` flag ensures Cargo.lock versions are used
- cargo audit scans for known vulnerabilities
- Leo's Cargo.lock pins exact versions

**Residual Risk**: Zero-day supply chain attacks (not yet in RustSec database).

### T3: Compromised rustup.rs

**Threat**: Official Rust installer is compromised.

**Likelihood**: Very Low (Rust project has strong security practices)

**Impact**: Critical (malicious compiler)

**Mitigations**:
- rustup.rs is operated by the Rust project
- Downloads over HTTPS with TLS 1.2+
- Could add rustup signature verification (not currently implemented)

**Residual Risk**: Accepted as baseline trust for any Rust project.

### T4: Cache Poisoning

**Threat**: Attacker poisons GitHub Actions cache with malicious binary.

**Likelihood**: Very Low (requires repo access or GitHub infrastructure compromise)

**Impact**: High (malicious binary restored from cache)

**Mitigations**:
- Caches are scoped to repository
- Cache keys include version (attacker cannot inject into different version)
- GitHub-operated cache service

**Residual Risk**: If attacker has repo write access, they have simpler attack vectors.

### T5: Man-in-the-Middle on Downloads

**Threat**: Attacker intercepts git clone or cargo downloads.

**Likelihood**: Very Low (GitHub runner networks are controlled)

**Impact**: High (malicious code or dependencies)

**Mitigations**:
- All connections use HTTPS
- TLS 1.2 minimum enforced
- Git and cargo verify certificates

### T6: Malicious Third-Party Action

**Threat**: Dependency action (actions/cache) is compromised.

**Likelihood**: Low (GitHub official actions have strong security)

**Impact**: Variable (depends on action's permissions)

**Mitigations**:
- SHA-pinned to specific commit (immutable)
- Only using GitHub's official actions
- Minimal actions used (only cache)

**Residual Risk**: GitHub could be compelled to modify historical commits (theoretical, never observed).

## Security Controls Summary

| Control | Implementation | Status |
|---------|----------------|--------|
| Source build only | cargo build --locked | ✅ Enforced |
| Dependency pinning | --locked flag | ✅ Enforced |
| Vulnerability scanning | cargo audit | ✅ Optional (default on) |
| SHA-pinned actions | actions/cache@SHA | ✅ Enforced |
| TLS 1.2+ only | curl/git flags | ✅ Enforced |
| Tag verification | git describe --exact-match | ✅ Enforced |
| No third-party binary tools | N/A | ✅ Enforced |

---

# Criteria for Enabling Binary Downloads

This action can support pre-built binary downloads when ProvableHQ implements **at least one** of the following verification mechanisms:

## Option 1: GPG-Signed Releases

**Requirements**:
- Release tags signed with GPG key
- Public key published in multiple locations (website, keyservers, README)
- Key fingerprint documented in SECURITY_MODEL.md or similar

**Verification method**:
```bash
git verify-tag v3.4.0
gpg --verify leo-v3.4.0.tar.gz.asc leo-v3.4.0.tar.gz
```

## Option 2: Sigstore/Cosign Signatures

**Requirements**:
- Binaries signed with cosign
- Signatures published alongside releases (.sig files)
- Certificate identity documented (email or OIDC issuer)

**Verification method**:
```bash
cosign verify-blob \
  --certificate leo-v3.4.0.pem \
  --signature leo-v3.4.0.sig \
  --certificate-identity release@provablehq.com \
  --certificate-oidc-issuer https://accounts.google.com \
  leo-v3.4.0-x86_64-unknown-linux-gnu.zip
```

## Option 3: SLSA Provenance Attestations

**Requirements**:
- SLSA Level 2+ attestations
- Provenance published to Rekor transparency log or as release asset
- Build instructions match published workflow

**Verification method**:
```bash
slsa-verifier verify-artifact \
  --provenance-path leo-v3.4.0.intoto.jsonl \
  --source-uri github.com/ProvableHQ/leo \
  --source-tag v3.4.0 \
  leo-v3.4.0-x86_64-unknown-linux-gnu.zip
```

## Option 4: GitHub Artifact Attestations

**Requirements**:
- Using `actions/attest-build-provenance` in release workflow
- Attestations viewable via `gh attestation verify`

**Verification method**:
```bash
gh attestation verify leo-v3.4.0-x86_64-unknown-linux-gnu.zip \
  --owner ProvableHQ
```

---

# Action Repository Security Practices

This action repository itself follows security best practices:

## Practices Implemented

- [ ] **All dependencies SHA-pinned**: actions/cache pinned to specific commit
- [ ] **Minimal permissions**: Action requires no special permissions
- [ ] **No secrets**: Action doesn't use or expose secrets
- [ ] **Auditable code**: ~400 lines of bash, fully readable
- [ ] **No external downloads in action code**: Only git clone and cargo build
- [ ] **Branch protection**: (Configure in your fork)
- [ ] **Signed commits**: (Configure in your fork)

## Recommended Repository Settings

For maintaining this action, enable:

1. **Branch protection on main**:
   - Require PR reviews
   - Require status checks
   - Require signed commits (if possible)
   - Disallow force pushes

2. **Security features**:
   - Dependabot alerts
   - Secret scanning
   - Code scanning (CodeQL)

3. **Access control**:
   - Minimal write access
   - Require 2FA for all contributors

---

# Changelog

| Date | Change |
|------|--------|
| 2025-12-22 | Initial security documentation |

---

# References

- [GitHub Actions Security Hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
- [SLSA Supply Chain Security](https://slsa.dev/)
- [Sigstore](https://www.sigstore.dev/)
- [tj-actions Compromise Analysis](https://www.stepsecurity.io/blog/tj-actions-changed-files-compromise)
- [RustSec Advisory Database](https://rustsec.org/)
