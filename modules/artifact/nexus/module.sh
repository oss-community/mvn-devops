# shellcheck shell=bash
# Nexus 3: replaces the generated admin password and accepts the community
# EULA.  The default maven-releases and maven-snapshots repositories are used.

module_secrets() {
  ask NEXUS_HOST_PORT "Nexus port on this machine" 8084
  ask_secret NEXUS_ADMIN_PASSWORD "New Nexus admin password" "$(random_password)"
  log_dim "  Nexus Community Edition accepts uploads only after you accept its EULA:"
  log_dim "  https://links.sonatype.com/products/nxrm/ce-eula"
  ask NEXUS_ACCEPT_EULA "Accept the Nexus Community Edition EULA? yes/no" no
}

nexus_api() {
  local auth=$1 method=$2 path=$3; shift 3
  curl -s -u "$auth" -X "$method" "$(host_url "$(value NEXUS_HOST_PORT)")/service/rest$path" "$@"
}

module_configure() {
  local password initial status eula
  password=$(require_value NEXUS_ADMIN_PASSWORD)
  wait_http "$(host_url "$(value NEXUS_HOST_PORT)")/service/rest/v1/status" 600 '^200$' \
    || die "Nexus did not start. Check '$DEVOPS_CMD logs nexus'."

  initial=$(compose exec -T nexus cat /nexus-data/admin.password 2>/dev/null || true)
  if [[ -n $initial ]]; then
    status=$(nexus_api "admin:$initial" PUT /v1/security/users/admin/change-password \
      -H 'Content-Type: text/plain' --data-raw "$password" -o /dev/null -w '%{http_code}')
    [[ $status == 204 ]] || die "Could not change the Nexus admin password (HTTP $status)."
    compose exec -T nexus rm -f /nexus-data/admin.password > /dev/null 2>&1 || true
    log_ok "Replaced the generated admin password"
  fi

  status=$(nexus_api "admin:$password" GET /v1/status/check -o /dev/null -w '%{http_code}')
  [[ $status == 200 ]] || die "Nexus rejects admin with NEXUS_ADMIN_PASSWORD (HTTP $status)."

  # Nexus Community Edition (3.77+) refuses uploads until the EULA is accepted.
  eula=$(nexus_api "admin:$password" GET /v1/system/eula 2>/dev/null || true)
  if [[ $(jq -r '.accepted' <<< "$eula" 2>/dev/null) == false ]]; then
    if [[ $(value NEXUS_ACCEPT_EULA no) =~ ^[Yy] ]]; then
      status=$(nexus_api "admin:$password" POST /v1/system/eula -H 'Content-Type: application/json' \
        --data "$(jq -c '.accepted = true' <<< "$eula")" -o /dev/null -w '%{http_code}')
      [[ $status == 204 || $status == 200 ]] || die "Could not accept the Nexus EULA (HTTP $status)."
      log_ok "Accepted the Nexus Community Edition EULA"
    else
      log_warn "The Nexus EULA is not accepted, so deploys to Nexus will fail. Accept it in the UI,"
      log_warn "or set NEXUS_ACCEPT_EULA with '$DEVOPS_CMD secrets --reconfigure' and run configure again."
    fi
  fi
}

module_env() {
  local base
  base=$(pipeline_url nexus 8081 "$(value NEXUS_HOST_PORT 8084)")
  pipeline_var NEXUS_ARTIFACTORY_USERNAME admin
  pipeline_secret NEXUS_ARTIFACTORY_PASSWORD "$(value NEXUS_ADMIN_PASSWORD)"
  pipeline_var NEXUS_ARTIFACTORY_HOST_URL "$base"
  pipeline_var NEXUS_ARTIFACTORY_SNAPSHOT_URL "$base/repository/maven-snapshots/"
  pipeline_var NEXUS_ARTIFACTORY_RELEASE_URL "$base/repository/maven-releases/"
}

module_stages() {
  stage 72 cd deploy-nexus "deploy -DskipTests=true -P nexus"
}

module_urls() {
  printf '  %-12s %s   (admin / devops.sh get NEXUS_ADMIN_PASSWORD)\n' Nexus "$(host_url "$(value NEXUS_HOST_PORT 8084)")"
}
