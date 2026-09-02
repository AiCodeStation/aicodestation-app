# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 1.0.30 (current) | Yes |
| Older 1.0.x | Please update before reporting |

We ship fixes in the current release line. If you are on an older build, update first and confirm
the issue still reproduces.

## Reporting a vulnerability

We welcome responsible disclosure.

Report through [aicodestation.com/contact](https://aicodestation.com/contact/) and mark the message
as a security disclosure. Please do not open a public GitHub issue for a vulnerability.

Include what you have:

- The version and platform you tested (Help, About shows the exact build)
- Steps to reproduce, or a proof of concept
- What an attacker gains, and any preconditions they need
- Logs or screenshots, with anything sensitive redacted

## What to expect

- We acknowledge reports and tell you whether we can reproduce the issue.
- We keep you updated while we work on a fix.
- We credit reporters who want the credit, once a fix has shipped.

## Please do not

- Run denial of service or load tests against our services
- Access, modify, or exfiltrate data that is not yours
- Use social engineering against our staff or our customers

## Verifying a release

Every release file is GPG signed and its SHA-256 is published. The signing key is not held on the
website server or the download server. Verification steps and the key fingerprint are in the
[README](README.md#verify-what-you-downloaded) and on the
[downloads page](https://aicodestation.com/downloads/).

## Our security posture

The product security model, data handling, and subprocessor detail are documented in the
[Trust Center](https://aicodestation.com/security/).
