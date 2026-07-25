# Security

## Secrets that must never enter this repository

- `.torrent` files
- Tracker announce URLs
- PT passkeys, authkeys, cookies, session tokens
- qBittorrent WebUI passwords
- VPS private keys

The `.gitignore` blocks common torrent and credential filenames, but users must still inspect every commit.

## Reporting

For security-sensitive deployment issues, do not include live domains, public IPs, passwords, passkeys, or complete logs in a public issue. Redact secrets first.

## Design choices

- qBittorrent runs as an unprivileged system account.
- Port 8080 is not opened in UFW.
- HTTPS terminates at Caddy.
- CSRF, Host Header validation, Clickjacking protection and authentication remain enabled.
- The installer refuses to overwrite a pre-existing custom Caddy configuration.
- No tracker automation, fake upload, modified client or passkey handling is included.
