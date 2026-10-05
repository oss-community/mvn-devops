# shellcheck shell=bash
# SonarQube: starts the server, replaces the default admin password and
# creates the analysis token the pipeline uses.

module_secrets() {
  ask SONAR_HOST_PORT "SonarQube port on this machine" 9000
  ask SONAR_DB "SonarQube database name" sonar
  ask SONAR_DB_USER "SonarQube database user" sonar
  ask_secret SONAR_DB_PASSWORD "SonarQube database password" "$(random_password)"
  ask_secret SONAR_ADMIN_PASSWORD "New SonarQube admin password" "$(random_password)"
}

sonar_api() {
  local auth=$1 method=$2 path=$3; shift 3
  curl -s -u "$auth" -X "$method" "$(host_url "$(value SONAR_HOST_PORT)")$path" "$@"
}

sonar_valid() {
  [[ $(sonar_api "$1" GET /api/authentication/validate | jq -r '.valid' 2>/dev/null) == true ]]
}

module_configure() {
  local base admin_password status token start
  base=$(host_url "$(value SONAR_HOST_PORT)")
  admin_password=$(require_value SONAR_ADMIN_PASSWORD)

  printf '  waiting for SonarQube at %s ' "$base"
  start=$(date +%s)
  until [[ $(curl -s "$base/api/system/status" | jq -r '.status' 2>/dev/null) == UP ]]; do
    (( $(date +%s) - start > 600 )) && { printf ' timeout\n'; die "SonarQube did not start. Check '$DEVOPS_CMD logs sonarqube'."; }
    printf '.'; sleep 5
  done
  printf ' up\n'

  if sonar_valid "admin:admin"; then
    status=$(sonar_api admin:admin POST /api/users/change_password -o /dev/null -w '%{http_code}' \
      --data-urlencode login=admin --data-urlencode previousPassword=admin \
      --data-urlencode "password=$admin_password")
    [[ $status == 204 ]] || die "Could not change the SonarQube admin password (HTTP $status)."
    log_ok "Replaced the default admin password"
  elif ! sonar_valid "admin:$admin_password"; then
    die "SonarQube rejects admin with SONAR_ADMIN_PASSWORD. Fix it with '$DEVOPS_CMD secrets --reconfigure'."
  fi

  sonar_api "admin:$admin_password" POST /api/user_tokens/revoke -o /dev/null --data-urlencode name=mvn-devops
  token=$(sonar_api "admin:$admin_password" POST /api/user_tokens/generate --data-urlencode name=mvn-devops | jq -r '.token // empty')
  [[ -n $token ]] || die "Could not create a SonarQube token."
  set_value SONAR_TOKEN "$token" secret
  log_ok "Created analysis token 'mvn-devops'"
}

module_env() {
  pipeline_var SONAR_URL "$(pipeline_url sonarqube 9000 "$(value SONAR_HOST_PORT 9000)")"
  pipeline_secret SONAR_TOKEN "$(value SONAR_TOKEN)"
}

module_stages() {
  stage 45 ci sonar "sonar:sonar -P sonar"
}

module_urls() {
  printf '  %-12s %s   (admin / devops.sh get SONAR_ADMIN_PASSWORD)\n' SonarQube "$(host_url "$(value SONAR_HOST_PORT 9000)")"
}
