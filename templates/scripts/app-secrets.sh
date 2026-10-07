#!/bin/sh
# Prints the secrets of the application in one environment as a JSON object
# of names and values, read from Vault: the KV (version 2) secret
# $VAULT_KV_MOUNT/$VAULT_APP/<environment>.  Prints {} when there is no Vault
# (VAULT_ADDR is empty) or no secret at that path.  Renews the (periodic)
# token, so it stays valid while the pipeline uses it.
#
#   app-secrets.sh <environment>
set -eu

environment=$1
if [ -z "${VAULT_ADDR:-}" ]; then
  echo '{}'
  exit 0
fi
scripts=$(cd "$(dirname "$0")" && pwd)
jq=$(command -v jq 2> /dev/null || sh "$scripts/tool.sh" jq)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

curl -s -o /dev/null -X POST -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/auth/token/renew-self" || true
path=${VAULT_KV_MOUNT:-secret}/data/$VAULT_APP/$environment
status=$(curl -s -o "$work/secret.json" -w '%{http_code}' -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/$path")
case $status in
  200) "$jq" -c '.data.data // {} | with_entries(.value |= tostring)' "$work/secret.json" ;;
  404) echo '{}' ;;
  *)
    echo "app-secrets.sh: Vault answered HTTP $status for $path" >&2
    cat "$work/secret.json" >&2 2> /dev/null || true
    exit 1 ;;
esac
