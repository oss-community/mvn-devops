#!/bin/sh
# Prints the secrets of the application in one environment as a JSON object
# of names and values:
#
#   - with the database module (DATABASE_ENGINE), the connection to the
#     environment's database at <database host>: SPRING_DATASOURCE_URL,
#     _USERNAME and _PASSWORD;
#   - with Vault (VAULT_ADDR), the KV (version 2) secret
#     $VAULT_KV_MOUNT/$VAULT_APP/<environment>, which wins over the above.
#     The (periodic) token is renewed, so it stays valid while the pipeline
#     uses it.
#
# Prints {} when there are none.
#
#   app-secrets.sh <environment> [database host]
set -eu

environment=$1
db_host=${2:-}
scripts=$(cd "$(dirname "$0")" && pwd)

json() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }

database='{}'
if [ "${DATABASE_ENGINE:-}" = postgresql ] && [ -n "$db_host" ]; then
  case $environment in
    staging) password=${DATABASE_STAGING_PASSWORD:-} ;;
    production) password=${DATABASE_PRODUCTION_PASSWORD:-} ;;
    *) password='' ;;
  esac
  database="{\"SPRING_DATASOURCE_URL\": $(json "jdbc:postgresql://$db_host:5432/$DATABASE_NAME"),"
  database="$database \"SPRING_DATASOURCE_USERNAME\": $(json "$DATABASE_NAME"), \"SPRING_DATASOURCE_PASSWORD\": $(json "$password")}"
fi

if [ -z "${VAULT_ADDR:-}" ]; then
  printf '%s\n' "$database"
  exit 0
fi
jq=$(command -v jq 2> /dev/null || sh "$scripts/tool.sh" jq)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

curl -s -o /dev/null -X POST -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/auth/token/renew-self" || true
path=${VAULT_KV_MOUNT:-secret}/data/$VAULT_APP/$environment
status=$(curl -s -o "$work/secret.json" -w '%{http_code}' -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/$path")
case $status in
  200) ;;
  404) echo '{}' > "$work/secret.json" ;;
  *)
    echo "app-secrets.sh: Vault answered HTTP $status for $path" >&2
    cat "$work/secret.json" >&2 2> /dev/null || true
    exit 1 ;;
esac
"$jq" -c --argjson db "$database" '$db + (.data.data // {} | with_entries(.value |= tostring))' "$work/secret.json"
