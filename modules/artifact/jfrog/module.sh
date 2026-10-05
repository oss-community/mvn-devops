# shellcheck shell=bash
# JFrog Artifactory OSS: replaces the default admin password, tries to create
# the Maven repositories and fetches the encrypted password the
# artifactory-maven-plugin uses.

module_secrets() {
  ask JFROG_HOST_PORT "Artifactory port on this machine" 8082
  ask JFROG_ARTIFACTORY_REPOSITORY_PREFIX "Repository prefix (<prefix>-libs-release-local)" "$(printf '%s' "$PROJECT_NAME" | cut -d- -f1)"
  ask JFROG_DB "Artifactory database name" artifactory
  ask JFROG_DB_USER "Artifactory database user" artifactory
  ask_secret JFROG_DB_PASSWORD "Artifactory database password" "$(random_password)"
  ask_secret JFROG_ADMIN_PASSWORD "New Artifactory admin password" "$(random_password)"
}

jfrog_api() {
  local auth=$1 method=$2 path=$3; shift 3
  curl -s -u "$auth" -X "$method" "$(host_url "$(value JFROG_HOST_PORT)")/artifactory/api$path" "$@"
}

jfrog_auth_ok() {
  [[ $(jfrog_api "$1" GET /security/encryptedPassword -o /dev/null -w '%{http_code}') == 200 ]]
}

module_configure() {
  local password prefix key kind status encrypted body manual=0
  password=$(require_value JFROG_ADMIN_PASSWORD)
  prefix=$(value JFROG_ARTIFACTORY_REPOSITORY_PREFIX)

  wait_http "$(host_url "$(value JFROG_HOST_PORT)")/artifactory/api/system/ping" 900 '^200$' \
    || die "Artifactory did not start. Check '$DEVOPS_CMD logs jfrog'."

  if jfrog_auth_ok "admin:password"; then
    body=$(jq -nc --arg p "$password" '{userName: "admin", oldPassword: "password", newPassword1: $p, newPassword2: $p}')
    status=$(jfrog_api admin:password POST /security/users/authorization/changePassword \
      -H 'Content-Type: application/json' --data "$body" -o /dev/null -w '%{http_code}')
    if [[ $status == 200 ]]; then
      log_ok "Replaced the default admin password"
    else
      log_warn "Could not change the default password (HTTP $status). Log in with admin/password and set it to JFROG_ADMIN_PASSWORD."
    fi
  fi
  jfrog_auth_ok "admin:$password" || die "Artifactory rejects admin with JFROG_ADMIN_PASSWORD. Change it in the UI or run '$DEVOPS_CMD secrets --reconfigure'."

  for kind in release snapshot; do
    key="$prefix-libs-$kind-local"
    if [[ $(jfrog_api "admin:$password" GET "/repositories/$key" -o /dev/null -w '%{http_code}') == 200 ]]; then
      log_dim "  repository $key exists"
      continue
    fi
    body=$(jq -nc --arg k "$key" --arg kind "$kind" \
      '{key: $k, rclass: "local", packageType: "maven", handleReleases: ($kind == "release"), handleSnapshots: ($kind == "snapshot")}')
    status=$(jfrog_api "admin:$password" PUT "/repositories/$key" -H 'Content-Type: application/json' --data "$body" -o /dev/null -w '%{http_code}')
    if [[ $status == 200 ]]; then log_ok "Created repository $key"; else manual=1; fi
  done
  if (( manual )); then
    log_warn "Artifactory OSS does not allow creating repositories through the API."
    log_warn "Open $(host_url "$(value JFROG_HOST_PORT)"), choose 'Quick Setup' > Maven and use the prefix '$prefix'."
  fi

  encrypted=$(jfrog_api "admin:$password" GET /security/encryptedPassword)
  [[ -n $encrypted ]] || die "Could not fetch the encrypted admin password."
  set_value JFROG_ARTIFACTORY_ENCRYPTED_PASSWORD "$encrypted" secret
  log_ok "Stored the encrypted password for the pipeline"
}

module_env() {
  local context prefix
  context=$(pipeline_url jfrog 8082 "$(value JFROG_HOST_PORT 8082)" /artifactory)
  prefix=$(value JFROG_ARTIFACTORY_REPOSITORY_PREFIX)
  pipeline_var JFROG_ARTIFACTORY_USERNAME admin
  pipeline_secret JFROG_ARTIFACTORY_ENCRYPTED_PASSWORD "$(value JFROG_ARTIFACTORY_ENCRYPTED_PASSWORD)"
  pipeline_var JFROG_ARTIFACTORY_CONTEXT_URL "$context"
  pipeline_var JFROG_ARTIFACTORY_REPOSITORY_PREFIX "$prefix"
  pipeline_var JFROG_ARTIFACTORY_RELEASE_URL "$context/$prefix-libs-release-local/"
  pipeline_var JFROG_ARTIFACTORY_SNAPSHOT_URL "$context/$prefix-libs-snapshot-local/"
}

module_stages() {
  stage 70 cd deploy-jfrog "deploy -DskipTests=true -P jfrog"
}

module_urls() {
  printf '  %-12s %s   (admin / devops.sh get JFROG_ADMIN_PASSWORD)\n' Artifactory "$(host_url "$(value JFROG_HOST_PORT 8082)")"
}
