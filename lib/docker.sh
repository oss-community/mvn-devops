# shellcheck shell=bash
# Docker compose wrapper and readiness checks.

compose_project() {
  printf 'devops-%s' "$(printf '%s' "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-\n' '-')"
}

# compose <docker compose args...>
compose() {
  local -a files=()
  local file
  while IFS= read -r file; do
    [[ -n $file ]] && files+=(-f "$file")
  done < <(compose_files)
  if (( ${#files[@]} == 0 )); then
    log_dim "No selected module needs containers."
    return 0
  fi
  command -v docker > /dev/null || die "docker is not installed"
  docker compose --project-name "$(compose_project)" \
    --project-directory "$DEVOPS_STATE" \
    --env-file "$DEVOPS_ENV/compose.env" \
    "${files[@]}" "$@"
}

# wait_http <url> [timeout seconds] [accepted status regex]
wait_http() {
  local url=$1 timeout=${2:-300} accept=${3:-'^(200|401|403)$'} start code
  start=$(date +%s)
  printf '  waiting for %s ' "$url"
  while true; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)
    if [[ $code =~ $accept ]]; then
      printf ' up\n'
      return 0
    fi
    if (( $(date +%s) - start > timeout )); then
      printf ' timeout\n'
      return 1
    fi
    printf '.'
    sleep 5
  done
}
