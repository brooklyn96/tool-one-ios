# Security policy

## Reporting

Report suspected vulnerabilities privately through GitHub Security Advisories.
Do not include access tokens, device codes, personal data, or production logs
in a public issue.

## Client security boundary

Tool One stores session material in the iOS Keychain and permits HTTPS only.
The repository contains no backend implementation or server credential. Public
API origins, OAuth host allowlists, bundle identifiers, and route names are not
authorization controls; the private backend must authenticate and authorize
every request independently.

Official IPA releases are unsigned LiveContainer guest applications. Verify the
release tag and download only from this repository's Releases page.
