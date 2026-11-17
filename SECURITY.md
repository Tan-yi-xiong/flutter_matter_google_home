# Security Policy

## Reporting

Do not open a public issue for a vulnerability involving onboarding payloads,
passcodes, credentials, certificates, private keys, or device identifiers.
Report the issue privately to the repository owner with enough detail to
reproduce it, using sanitized logs only.

## Secret handling

- Treat Matter onboarding payloads, passcodes, operational IP addresses,
  Wi-Fi credentials, and Thread datasets as secrets.
- `GoogleHomeMatterHandoff` is in-memory only.
- Do not persist handoff objects or include them in logs, screenshots, crash
  reports, CI artifacts, or GitHub issues.
- Do not commit Google Home SDK artifacts or local Maven repositories.
