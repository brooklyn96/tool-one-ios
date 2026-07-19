# Tool One for iOS

Tool One is a native SwiftUI workspace for selected BeyondK workflows. This
public repository contains only the iOS client, test fixtures, and the minimal
GitHub Actions pipeline required to produce an unsigned IPA for LiveContainer.

## What is intentionally absent

- Backend and gateway implementations
- Database schemas, migrations, and production data
- VPS inventory, deployment scripts, service configuration, and runbooks
- Credentials, OAuth client secrets, signing identities, and provisioning files

Production HTTPS origins and application route names are client routing
identifiers, not credentials. Authorization is enforced by the private backend.

## Build

The release workflow runs only when an owner pushes a `v*` tag. A manual run
produces a temporary Actions artifact; a tagged run publishes `ToolOne.ipa` as
a GitHub Release asset. The IPA is unsigned and targets LiveContainer on iOS 16
or later.

Local macOS requirements:

```bash
brew install xcodegen
bash scripts/test-ios.sh
bash scripts/build-unsigned-ipa.sh
bash scripts/verify-ipa.sh dist/ToolOne.ipa
```

## Security

Please report vulnerabilities privately through GitHub Security Advisories.
Do not post tokens, production logs, personal data, or device session material
in public issues.
