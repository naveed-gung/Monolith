# Security Policy

## Public Repository Safety

Monolith may be published as a public repository. To keep it safe:

- never commit certificates, provisioning profiles, private keys, or keystores
- never commit `.env` files with real tokens or credentials
- never commit generated IPA, debug, or release build artifacts
- never store signing or deployment secrets in tracked JSON, YAML, plist, or shell files

Sensitive files that must stay out of version control include:

- `*.p12`
- `*.mobileprovision`
- `*.pem`
- `*.key`
- `*.jks`
- `*.keystore`
- `.env`
- `.env.*`
- `dist/`
- `*.ipa`
- `*.xcarchive`
- `*.xcresult`

## GitHub Actions

The prepared iOS workflow is manual-only by design. Keep it that way unless you intentionally want automatic cloud builds.

If code signing is added later, store signing material only in GitHub Secrets, not in the repository.

## Reporting

If you discover a security issue in Monolith, do not open a public issue containing secrets, certificates, tokens, or private device information.

Instead, sanitize the report first and remove:

- API tokens
- bundle identifiers tied to personal accounts
- provisioning profile contents
- certificate material
- device identifiers
