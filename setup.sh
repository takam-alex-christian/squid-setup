#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ACCOUNTS_FILE="$SCRIPT_DIR/accounts.yaml"
PASSWORD_FILE="$SCRIPT_DIR/passwords"

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is required but was not found in PATH." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Error: Docker Compose v2 is required." >&2
  exit 1
fi

if [[ ! -f "$ACCOUNTS_FILE" ]]; then
  echo "Error: accounts file not found: $ACCOUNTS_FILE" >&2
  exit 1
fi

# The generated password database is mounted into the container. Creating it
# before `docker compose up` prevents Docker from treating the mount source as
# a directory on a fresh checkout.
touch "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

echo "Starting Squid..."
docker compose -f "$COMPOSE_FILE" up -d squid

echo "Installing apache2-utils in the Squid container..."
docker exec squid apt-get update
docker exec squid apt-get install -y apache2-utils

accounts=()
while IFS= read -r account; do
  accounts+=("$account")
done < <(
  awk '
    /^accounts:[[:space:]]*$/ {
      in_accounts = 1
      next
    }

    in_accounts && /^[^[:space:]#]/ {
      exit
    }

    in_accounts && /^[[:space:]]*-[[:space:]]*username:[[:space:]]*/ {
      username = $0
      sub(/^[[:space:]]*-[[:space:]]*username:[[:space:]]*/, "", username)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", username)
      next
    }

    in_accounts && /^[[:space:]]*password:[[:space:]]*/ {
      password = $0
      sub(/^[[:space:]]*password:[[:space:]]*/, "", password)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", password)

      if (username == "" || password == "") {
        print "ERROR: each account must include a non-empty username and password" > "/dev/stderr"
        exit 2
      }

      print username "\t" password
      username = ""
      password = ""
    }
  ' "$ACCOUNTS_FILE"
)

if [[ "${#accounts[@]}" -eq 0 ]]; then
  echo "Error: no accounts were found in $ACCOUNTS_FILE." >&2
  exit 1
fi

first_account=1
for account in "${accounts[@]}"; do
  IFS=$'\t' read -r username password <<< "$account"

  if [[ "$first_account" -eq 1 ]]; then
    echo "Creating password database with account: $username"
    docker exec squid htpasswd -cb /etc/squid/passwords "$username" "$password"
    first_account=0
  else
    echo "Adding account: $username"
    docker exec squid htpasswd -b /etc/squid/passwords "$username" "$password"
  fi
done

echo "Reloading Squid configuration..."
docker exec squid squid -k reconfigure

echo "Squid proxy is ready on port 3128."
