# Squid proxy setup

This directory contains a Docker Compose deployment for an authenticated Squid proxy.

## Setup

1. Edit `accounts.yaml` and add or remove accounts.
2. Run the setup script:

   ```sh
   ./setup.sh
   ```

The script starts the `squid` container, installs `apache2-utils`, creates the NCSA password database with `htpasswd`, and reloads Squid. The generated `passwords` file is intentionally ignored by Git.

The proxy listens on port `3128` and requires credentials for every request.

## Account format

Use this YAML shape:

```yaml
accounts:
  - username: user1
    password: secret123
  - username: user2
    password: another-secret
```

The setup script expects each account to have one `username` and one `password` field. Keep values on a single line and avoid tabs in credentials.
