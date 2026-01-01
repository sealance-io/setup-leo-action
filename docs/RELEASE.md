# Release Process

This document describes how to release new versions of setup-leo-action.

## Versioning Strategy

This action uses **immutable semantic versioning**:
- Users reference full versions: `@v1.0.0`, `@v1.2.3`
- No floating major tags (`@v1`) - maximizes supply chain security
- Pre-releases use hyphenated versions: `v1.0.0-beta.1`, `v2.0.0-rc.1`

## Creating a Release

### 1. Ensure CI passes

All tests must pass on the `main` branch before releasing.

### 2. Create and push a tag

```bash
# For stable releases
git tag -a v1.0.0 -m "Release v1.0.0: Brief description"
git push origin v1.0.0

# For pre-releases
git tag -a v1.0.0-beta.1 -m "Pre-release v1.0.0-beta.1"
git push origin v1.0.0-beta.1
```

### 3. Automated release

The release workflow (`.github/workflows/release.yml`) automatically:
- Creates a GitHub Release
- Generates release notes from commits
- Adds installation instructions with tag and SHA
- Marks pre-releases appropriately
- Sets stable releases as "latest"

## Version Numbering

| Change Type | Version Bump | Example |
|-------------|--------------|---------|
| Breaking changes to inputs/outputs | Major | v1.0.0 → v2.0.0 |
| New features, new inputs (backward compatible) | Minor | v1.0.0 → v1.1.0 |
| Bug fixes, documentation, internal changes | Patch | v1.0.0 → v1.0.1 |

### What constitutes a breaking change?

- Removing or renaming an input
- Changing default behavior
- Removing or renaming an output
- Changing output format/values
- Dropping support for a runner OS

## Pre-release Testing

Before a major release, consider a pre-release:

```bash
git tag -a v2.0.0-rc.1 -m "Release candidate for v2.0.0"
git push origin v2.0.0-rc.1
```

Pre-releases:
- Appear in GitHub Releases with "Pre-release" badge
- Are NOT marked as "latest"
- Allow early adopters to test

## Updating Leo Versions

When a new Leo version is released:

1. Verify the release:
   ```bash
   ./scripts/verify-release.sh <version>
   ```

2. Check required Rust version:
   ```bash
   curl -s "https://raw.githubusercontent.com/ProvableHQ/leo/v<VERSION>/rust-toolchain.toml"
   ```

3. Update `.github/workflows/test.yml`:
   - Add to `test-leo-versions` matrix
   - Update `LEO_VERSION` env var if it should be the new default

4. Create a patch release documenting Leo version support.

## Post-Release Checklist

- [ ] Verify release appears on GitHub Releases page
- [ ] Verify release notes are accurate
- [ ] Test installation with new tag:
  ```yaml
  - uses: sealance-io/setup-leo-action@v1.0.0
  ```
- [ ] Update examples in README.md if needed

## Immutable Releases (GitHub Setting)

This repository uses GitHub's immutable releases feature:
- Release assets cannot be modified after publication
- Git tags cannot be deleted or moved
- Provides automatic attestations for verification

To enable (one-time setup): **Settings → General → Releases → Require immutable releases**

## Rollback

If a release has critical issues:

1. **Do NOT delete the tag** (immutable releases prevent this anyway)
2. Create a new patch release with the fix:
   ```bash
   git tag -a v1.0.1 -m "Fix critical issue in v1.0.0"
   git push origin v1.0.1
   ```
3. Update release notes for v1.0.0 to note the issue and point to v1.0.1
