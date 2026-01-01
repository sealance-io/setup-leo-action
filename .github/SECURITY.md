# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| v1.x.x  | Yes       |

## Reporting a Vulnerability

Please report security vulnerabilities via GitHub's private vulnerability reporting:
1. Go to Security tab > Advisories > Report a vulnerability
2. Provide detailed reproduction steps

Expected response time: 5 business days for initial triage.

## Security Design

This action is designed with security-first principles:
- Builds Leo from source (no untrusted binaries)
- All dependencies SHA-pinned
- Minimal permissions model
- See docs/THREAT_MODEL.md for full analysis
