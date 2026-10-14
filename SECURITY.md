# Security

## Supported versions

Foundry is under active development. Security fixes are developed against the
current development branch; older development snapshots are not guaranteed to
receive backports.

## Reporting a vulnerability

If GitHub private vulnerability reporting is enabled, use **Security → Report
a vulnerability** in this repository.

If that option is unavailable, contact the maintainer through a private contact
method listed on [the maintainer's GitHub profile](https://github.com/doobox).
If no private contact method is available, open an issue requesting a private
security-reporting channel without including vulnerability details.

Please include the affected revision, reproduction steps, expected impact and
any suggested fix. Remove credentials and personal data from sample projects
and logs. Do not post exploitable details, passwords, private keys or access
tokens in public issues.

## Preview and extensions

Foundry previews website content, including JavaScript and PHP from part
packages. Only open projects and install packages from sources you trust.
Use test publishing destinations when investigating a security issue.

## Checking source before publication

Scan both the current source (including files not yet committed) and the complete
Git history before making the repository public or publishing a release.
[Gitleaks](https://github.com/gitleaks/gitleaks) can scan the history locally:

```sh
gitleaks git --log-opts='--all --full-history' --redact=100 --ignore-gitleaks-allow .
```

For the current source, scan a temporary copy of tracked files and non-ignored
untracked files. Include changed files, without including local build products
or private configuration excluded from Git. Keep any scan reports private and
redacted. If a real credential is found, revoke or rotate it; deleting it from
the latest revision alone does not remove it from history.
