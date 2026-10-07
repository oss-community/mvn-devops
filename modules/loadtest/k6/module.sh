# shellcheck shell=bash
# Load test of staging with k6, between the deployment to staging and the
# approval of production (templates/scripts/load-test.sh).  The stage fails
# when the thresholds fail: by default more than 1% failed requests or a 95th
# percentile response time above 500 ms.  The project's own k6 script
# (LOAD_TEST_SCRIPT) replaces the generic one (templates/scripts/load-test.js).
# With the prometheus module the results go to Prometheus too.

module_secrets() {
  local found=''
  if [[ " $MODULES " != *" deploy/"* ]]; then
    ask LOAD_TEST_URL "URL of staging the load test calls, e.g. https://staging.example.com" ""
  else
    found=$(app_address staging host)
    [[ -n $found ]] || ask LOAD_TEST_URL "URL of staging the load test calls (a cluster of its own)" ""
  fi
  [[ -n $found || -n $(value LOAD_TEST_URL) ]] || die "The load test needs LOAD_TEST_URL, the address of staging."
  ask LOAD_TEST_SCRIPT "k6 script of the project (empty: call LOAD_TEST_PATHS)" ""
  ask LOAD_TEST_PATHS "Paths the generic script calls, comma separated" /actuator/health
  ask LOAD_TEST_VUS "Virtual users" 10
  ask LOAD_TEST_DURATION "Duration" 30s
  ask LOAD_TEST_P95_MS "Highest 95th percentile response time (ms)" 500
  ask LOAD_TEST_MAX_ERROR_RATE "Highest share of failed requests" 0.01
}

# URL of staging as the pipeline reaches it.
staging_url() {
  local from=host
  if [[ -n $(value LOAD_TEST_URL) ]]; then
    value LOAD_TEST_URL
    return
  fi
  [[ ${DEVOPS_RUNS_IN:-host} == docker ]] && from=docker
  printf 'http://%s' "$(app_address staging "$from")"
}

module_env() {
  local key
  pipeline_var LOAD_TEST_URL "$(staging_url)"
  pipeline_var LOAD_TEST_HEALTH_PATH "$(value DEPLOY_HEALTH_PATH /actuator/health)"
  for key in LOAD_TEST_SCRIPT LOAD_TEST_PATHS LOAD_TEST_VUS LOAD_TEST_DURATION LOAD_TEST_P95_MS LOAD_TEST_MAX_ERROR_RATE; do
    pipeline_var "$key" "$(value "$key")"
  done
  if [[ " $MODULES " == *" monitoring/prometheus "* ]]; then
    pipeline_var LOAD_TEST_PROMETHEUS_URL "$(pipeline_url prometheus 9090 "$(value PROMETHEUS_HOST_PORT 9090)")"
  else
    pipeline_var LOAD_TEST_PROMETHEUS_URL ''
  fi
}

module_stages() {
  shell_stage 85 cd load-test "sh \"\$DEVOPS_SCRIPTS/load-test.sh\" staging"
}
