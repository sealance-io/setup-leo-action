#!/usr/bin/env bash
# =============================================================================
# verify-release.sh
#
# Verification script for new Leo releases.
# Run this before updating the action to use a new Leo version.
#
# Usage:
#   ./scripts/verify-release.sh 3.4.0
#
# This script will:
# 1. Check that the version exists as a git tag
# 2. Attempt to verify GPG signature (informational - will fail)
# 3. Check for SLSA attestations (informational - will fail)
# 4. Clone and verify Cargo.lock exists
# 5. Run cargo audit on the source
#
# =============================================================================

set -euo pipefail

VERSION="${1:-}"

if [[ -z "${VERSION}" ]]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 3.4.0"
    exit 1
fi

echo "=============================================="
echo "Verifying Leo v${VERSION} Release"
echo "=============================================="
echo ""
echo "Repository: https://github.com/ProvableHQ/leo"
echo "Version: v${VERSION}"
echo ""

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

# -----------------------------------------------------------------------------
# Check 1: Verify tag exists
# -----------------------------------------------------------------------------
echo "--- Check 1: Tag Exists ---"
if git ls-remote --tags https://github.com/ProvableHQ/leo "refs/tags/v${VERSION}" | grep -q "v${VERSION}"; then
    echo "✓ Tag v${VERSION} exists"
else
    echo "✗ Tag v${VERSION} NOT FOUND"
    echo "  Available tags:"
    git ls-remote --tags https://github.com/ProvableHQ/leo | tail -10
    exit 1
fi
echo ""

# -----------------------------------------------------------------------------
# Check 2: Clone specific tag
# -----------------------------------------------------------------------------
echo "--- Check 2: Clone Tag ---"
git clone --depth 1 --branch "v${VERSION}" \
    https://github.com/ProvableHQ/leo.git "${WORKDIR}/leo" 2>&1

cd "${WORKDIR}/leo"
COMMIT_SHA=$(git rev-parse HEAD)
echo "✓ Cloned successfully"
echo "  Commit: ${COMMIT_SHA}"
echo ""

# -----------------------------------------------------------------------------
# Check 3: GPG Signature (Informational)
# -----------------------------------------------------------------------------
echo "--- Check 3: GPG Signature (Informational) ---"
if git verify-tag "v${VERSION}" 2>/dev/null; then
    echo "✓ Tag is GPG signed and verified"
    SIGNED="true"
else
    echo "⚠ Tag is NOT GPG signed"
    echo "  This is expected for ProvableHQ releases"
    echo "  Reason: ProvableHQ does not sign their releases"
    SIGNED="false"
fi
echo ""

# -----------------------------------------------------------------------------
# Check 4: SLSA Attestations (Informational)
# -----------------------------------------------------------------------------
echo "--- Check 4: SLSA Attestations (Informational) ---"
RELEASE_URL="https://github.com/ProvableHQ/leo/releases/tag/v${VERSION}"
echo "Checking for .intoto.jsonl files in release assets..."

# This would require GitHub API; simplified check
if curl -sL "${RELEASE_URL}" | grep -q "intoto.jsonl"; then
    echo "✓ SLSA attestation found"
    SLSA="true"
else
    echo "⚠ No SLSA attestation found"
    echo "  This is expected for ProvableHQ releases"
    SLSA="false"
fi
echo ""

# -----------------------------------------------------------------------------
# Check 5: Cargo.lock Exists
# -----------------------------------------------------------------------------
echo "--- Check 5: Cargo.lock Verification ---"
if [[ -f "Cargo.lock" ]]; then
    echo "✓ Cargo.lock exists"
    DEPS=$(grep -c '^\[\[package\]\]' Cargo.lock || echo "0")
    echo "  Dependencies: ${DEPS} packages"
else
    echo "✗ Cargo.lock NOT FOUND"
    echo "  This is a security issue - dependencies are not pinned"
    exit 1
fi
echo ""

# -----------------------------------------------------------------------------
# Check 6: Cargo Audit
# -----------------------------------------------------------------------------
echo "--- Check 6: Security Audit ---"
if command -v cargo &>/dev/null; then
    if ! command -v cargo-audit &>/dev/null; then
        echo "Installing cargo-audit..."
        cargo install cargo-audit --locked --quiet
    fi
    
    echo "Running cargo audit..."
    if cargo audit 2>&1; then
        echo "✓ No known vulnerabilities"
        AUDIT="pass"
    else
        echo "⚠ Vulnerabilities found (see above)"
        AUDIT="warn"
    fi
else
    echo "⚠ Cargo not installed, skipping audit"
    AUDIT="skip"
fi
echo ""

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo "=============================================="
echo "Verification Summary for Leo v${VERSION}"
echo "=============================================="
echo ""
echo "| Check | Status |"
echo "|-------|--------|"
echo "| Tag exists | ✓ |"
echo "| Clone successful | ✓ |"
echo "| GPG signed | ${SIGNED} |"
echo "| SLSA attestation | ${SLSA} |"
echo "| Cargo.lock exists | ✓ |"
echo "| Security audit | ${AUDIT} |"
echo ""
echo "Commit SHA: ${COMMIT_SHA}"
echo ""

# -----------------------------------------------------------------------------
# Action Recommendation
# -----------------------------------------------------------------------------
echo "=============================================="
echo "Recommendation"
echo "=============================================="
if [[ "${SIGNED}" == "true" || "${SLSA}" == "true" ]]; then
    echo "✓ SAFE TO USE: Cryptographic verification available"
else
    echo "⚠ USE WITH CAUTION:"
    echo "  - No GPG signature"
    echo "  - No SLSA attestation"
    echo "  - Source build is the only safe option"
    echo ""
    echo "This action builds from source, which is appropriate."
fi
echo ""

# -----------------------------------------------------------------------------
# Update Instructions
# -----------------------------------------------------------------------------
echo "=============================================="
echo "To Update the Action"
echo "=============================================="
echo ""
echo "1. Update version in your workflow:"
echo "   version: '${VERSION}'"
echo ""
echo "2. Test in a branch first:"
echo "   git checkout -b update-leo-${VERSION}"
echo "   # Update workflow files"
echo "   git push origin update-leo-${VERSION}"
echo ""
echo "3. After verification, merge to main"
