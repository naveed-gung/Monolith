# iOS Builder Standby Setup

![Development workflow](assets/development-workflow.svg)

## Purpose

This document prepares Monolith for a future Windows-to-iPhone workflow using MobAI and `ios-builder`, without triggering any build right now.

The repository is intentionally set up in a standby state:

- no GitHub Action runs on push
- no signing secrets are committed
- no IPA, debug, or release artifacts are tracked
- no private credentials are required to review the setup

## What Is Already Prepared

### Manual-only GitHub Actions

The repository includes a manual-only workflow in `.github/workflows/ios.yml`.

Properties:

- trigger: `workflow_dispatch` only
- output: unsigned IPA artifact
- artifact name: `ipa`
- retention: 3 days

This means a public push alone will not start any macOS build.

### Public-safe Ignore Rules

The repository ignores:

- IPA files
- Xcode archives and results
- provisioning profiles
- certificates and private keys
- keystores
- local `.env` files
- local ios-builder override files
- `dist/` output

### ios-builder Template

A safe template exists at `builder.json.example`.

It is not live configuration yet and contains no secrets.

## Recommended Public Repo Rules

Before you create the public GitHub repo named `monolith`, keep these rules:

1. Do not commit `builder.json` with personal values until you have reviewed it.
2. Do not commit `.p12`, `.mobileprovision`, `.pem`, `.key`, `.jks`, or `.keystore` files.
3. Do not commit `dist/`, generated IPA files, or any Xcode archives.
4. Keep workflow triggers manual until you explicitly want cloud iOS builds.
5. Prefer unsigned IPA flow first. Add signing later only if truly needed.

## Suggested Activation Sequence Later

When you are ready, the later sequence should be:

1. Create the public GitHub repository named `monolith`.
2. Push the prepared files.
3. Copy `builder.json.example` to `builder.json` and replace `YOUR_GITHUB_USERNAME`.
4. Install MobAI on Windows and connect the iPhone.
5. Install `ios-builder`.
6. Authenticate with GitHub using `builder auth github`.
7. Manually dispatch the GitHub Action or run `builder ios build` when you want the first IPA.
8. Use `builder dev flutter` after the IPA install path is working.

## Signing Strategy

The standby setup uses unsigned IPA packaging by default.

That is the safer public-repo choice because:

- it avoids provisioning profiles in the repository
- it avoids certificate handling before you have confirmed the workflow
- MobAI can handle install/signing flow on the device side later

If you later decide to use signed builds, add GitHub Secrets only at that time:

- `IOS_CERTIFICATE`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE`

Do not add any of those values to tracked files.

## Commit-by-Commit Standby Plan

Because you want the work separated instead of one large commit, the clean file-by-file order is:

1. `.gitignore`
2. `.github/workflows/ios.yml`
3. `builder.json.example`
4. `docs/ios-builder-setup.md`
5. `README.md`
6. `docs/development.md`

That keeps public-repo hygiene, workflow behavior, config template, and docs isolated for review.

## Important Limitation

This setup only prepares the repository.

It does not:

- create the GitHub repo
- push anything
- trigger GitHub Actions
- build an IPA
- connect to MobAI
- attach Flutter debug tooling to your iPhone

Those steps require running commands or external services, and you explicitly asked not to do that yet.
