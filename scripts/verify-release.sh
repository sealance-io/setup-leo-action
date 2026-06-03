#!/usr/bin/env bash
# =============================================================================
# verify-release.sh
#
# Verification script for new Leo releases.
# Run this before updating the action to use a new Leo version.
#
# Usage:
#   ./scripts/verify-release.sh 4.1.0
#
# This script will:
# 1. Check that the version exists as a source tag
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
    echo "Example: $0 4.1.0"
    exit 1
fi

echo "=============================================="
echo "Verifying Leo ${VERSION} Release"
echo "=============================================="
echo ""
echo "Repository: https://github.com/ProvableHQ/leo"
echo "Version: ${VERSION}"
echo ""

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

# -----------------------------------------------------------------------------
# Check 1: Verify source tag exists
# -----------------------------------------------------------------------------
echo "--- Check 1: Source Tag Exists ---"
SOURCE_TAG=""
for TAG_CANDIDATE in "leo-lang-v${VERSION}" "v${VERSION}"; do
    echo "Checking tag: ${TAG_CANDIDATE}"
    if git ls-remote --exit-code --tags https://github.com/ProvableHQ/leo.git "refs/tags/${TAG_CANDIDATE}" >/dev/null 2>&1; then
        SOURCE_TAG="${TAG_CANDIDATE}"
        break
    fi
done

if [[ -n "${SOURCE_TAG}" ]]; then
    echo "✓ Tag ${SOURCE_TAG} exists"
else
    echo "✗ No source tag found for Leo ${VERSION}"
    echo "  Checked: leo-lang-v${VERSION}, v${VERSION}"
    echo "  Recent tags:"
    git ls-remote --tags https://github.com/ProvableHQ/leo.git | tail -10
    exit 1
fi
echo "  Resolved source tag: ${SOURCE_TAG}"
echo ""

# -----------------------------------------------------------------------------
# Check 2: Clone specific tag
# -----------------------------------------------------------------------------
echo "--- Check 2: Clone Tag ---"
git clone --depth 1 --branch "${SOURCE_TAG}" \
    https://github.com/ProvableHQ/leo.git "${WORKDIR}/leo" 2>&1

cd "${WORKDIR}/leo"
ACTUAL_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "unknown")
if [[ "${ACTUAL_TAG}" != "${SOURCE_TAG}" ]]; then
    echo "✗ Tag mismatch! Expected ${SOURCE_TAG}, got ${ACTUAL_TAG}"
    exit 1
fi

COMMIT_SHA=$(git rev-parse HEAD)
echo "✓ Cloned successfully"
echo "  Tag: ${SOURCE_TAG}"
echo "  Commit: ${COMMIT_SHA}"
echo ""

# -----------------------------------------------------------------------------
# Check 3: GPG Signature (Informational)
# -----------------------------------------------------------------------------
echo "--- Check 3: GPG Signature (Informational) ---"
if git verify-tag "${SOURCE_TAG}" 2>/dev/null; then
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
RELEASE_URL="https://github.com/ProvableHQ/leo/releases/tag/${SOURCE_TAG}"
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
# Check 6: Rust Toolchain
# -----------------------------------------------------------------------------
echo "--- Check 6: Rust Toolchain ---"
RUST_TOOLCHAIN="unknown"
if [[ -f "rust-toolchain.toml" ]]; then
    RUST_TOOLCHAIN=$(sed -n 's/^channel = "\(.*\)"/\1/p' rust-toolchain.toml | head -1)
    if [[ -n "${RUST_TOOLCHAIN}" ]]; then
        echo "✓ rust-toolchain.toml found"
        echo "  Required Rust: ${RUST_TOOLCHAIN}"
    else
        echo "⚠ rust-toolchain.toml found but channel could not be parsed"
    fi
else
    echo "⚠ rust-toolchain.toml not found"
fi
echo ""

# -----------------------------------------------------------------------------
# Check 7: Build Layout
# -----------------------------------------------------------------------------
echo "--- Check 7: Build Layout ---"
BUILD_LAYOUT="legacy-root"
BUILD_PACKAGE="(workspace root)"

if [[ -f "crates/leo/Cargo.toml" ]]; then
    BUILD_PACKAGE=$(awk '
        BEGIN { in_package = 0 }
        /^\[package\]/ { in_package = 1; next }
        /^\[/ { if (in_package) exit }
        in_package && $0 ~ /^name = "/ {
            sub(/^name = "/, "", $0)
            sub(/"$/, "", $0)
            print
            exit
        }
    ' "crates/leo/Cargo.toml")

    if [[ -z "${BUILD_PACKAGE}" ]]; then
        echo "✗ crates/leo/Cargo.toml does not define a package name"
        exit 1
    fi

    if awk '
        BEGIN { in_bin = 0; found = 0 }
        /^\[\[bin\]\]/ { in_bin = 1; next }
        /^\[/ { in_bin = 0 }
        in_bin && $0 ~ /^name = "leo"$/ { found = 1 }
        END { exit(found ? 0 : 1) }
    ' "crates/leo/Cargo.toml"; then
        BUILD_LAYOUT="crate-package"
        echo "✓ crates/leo layout detected"
        echo "  Package: ${BUILD_PACKAGE}"
        echo "  Binary target: leo"
    else
        echo "✗ crates/leo/Cargo.toml exists but no leo binary target was found"
        exit 1
    fi
elif [[ -f "Cargo.toml" ]]; then
    echo "✓ Legacy root build layout detected"
    echo "  Package: ${BUILD_PACKAGE}"
else
    echo "✗ Cargo.toml NOT FOUND"
    exit 1
fi
echo ""

# -----------------------------------------------------------------------------
# Check 8: Cargo Audit
# -----------------------------------------------------------------------------
echo "--- Check 8: Security Audit ---"
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
echo "Verification Summary for Leo ${VERSION}"
echo "=============================================="
echo ""
echo "| Check | Status |"
echo "|-------|--------|"
echo "| Source tag | ${SOURCE_TAG} |"
echo "| Tag exists | ✓ |"
echo "| Clone successful | ✓ |"
echo "| GPG signed | ${SIGNED} |"
echo "| SLSA attestation | ${SLSA} |"
echo "| Cargo.lock exists | ✓ |"
echo "| Rust toolchain | ${RUST_TOOLCHAIN} |"
echo "| Build layout | ${BUILD_LAYOUT} |"
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
