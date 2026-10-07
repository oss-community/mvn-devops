# shellcheck shell=bash
# Deploys the image of the commit to Kubernetes with Helm: the cd phase to
# the namespace <app>-staging, the prod phase to <app>-production once someone
# approves it.  Helm waits for a rolling update whose new pods pass their
# readiness probe and rolls back when they do not
# (templates/scripts/deploy-helm.sh).
#
# The cluster is an existing one, given by a kubeconfig file, or a one-node
# k3s cluster in Docker (compose.yml).  The chart is the project's
# (KUBERNETES_CHART) or the generic one in templates/helm/app.

ENVIRONMENTS='staging production'

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

module_secrets() {
  require_image_module
  ask_server KUBERNETES "Kubernetes cluster" https://k8s.example.com:6443
  if server_external KUBERNETES; then
    ask_local KUBERNETES_KUBECONFIG "Kubeconfig file with access to the cluster" "$HOME/.kube/config"
    ask KUBERNETES_STAGING_NODE_PORT "Node port of staging (empty: a ClusterIP service)" ""
    ask KUBERNETES_PRODUCTION_NODE_PORT "Node port of production (empty: a ClusterIP service)" ""
  else
    ask KUBERNETES_API_HOST_PORT "Kubernetes API port on the Docker machine" 6443
    ask KUBERNETES_STAGING_PORT "Port of staging on the Docker machine" 8281
    ask KUBERNETES_PRODUCTION_PORT "Port of production on the Docker machine" 8280
    set_value KUBERNETES_STAGING_NODE_PORT 30081
    set_value KUBERNETES_PRODUCTION_NODE_PORT 30080
  fi
  ask KUBERNETES_CHART "Helm chart of the application in the project (empty: the generic chart)" ""
  ask KUBERNETES_REPLICAS "Pods per environment" 2
  ask DEPLOY_HEALTH_PATH "Health check path of the application" /actuator/health
}

# up: the local registry is reached by its service name from the k3s node,
# and kubelet needs a flag on hosts that still use cgroup v1.
module_prepare() {
  local dir
  server_external KUBERNETES && return 0
  dir=$(k3s_dir)
  mkdir -p "$dir"
  {
    printf 'mirrors:\n'
    if [[ " $MODULES " == *" image/docker-registry "* ]] && ! server_external REGISTRY; then
      printf '  "localhost:%s":\n    endpoint:\n      - "http://registry:5000"\n' "$(value REGISTRY_HOST_PORT 5000)"
    fi
  } > "$dir/registries.yaml"
  if [[ $(docker info --format '{{.CgroupVersion}}' 2> /dev/null) == 1 ]]; then
    set_value K3S_EXTRA_ARGS '--kubelet-arg=fail-cgroupv1=false'
  else
    set_value K3S_EXTRA_ARGS ''
  fi
}

module_configure() {
  local file helm tries kc
  file="$(k3s_dir)/kubeconfig.yaml"
  if ! server_external KUBERNETES; then
    for (( tries = 0; tries < 90; tries++ )); do
      [[ -s $file ]] && break
      sleep 2
    done
    [[ -s $file ]] || die "k3s did not write its kubeconfig. Check '$DEVOPS_CMD logs k3s'."
  fi
  helm=$(sh "$DEVOPS_HOME/templates/scripts/tool.sh" helm) || die "Could not download Helm"
  kc=$(mktemp)
  kubeconfig host > "$kc"
  for (( tries = 0; tries < 60; tries++ )); do
    KUBECONFIG=$kc "$helm" list --all-namespaces > /dev/null 2>&1 && break
    sleep 2
  done
  if KUBECONFIG=$kc "$helm" list --all-namespaces > /dev/null 2>&1; then
    log_ok "Kubernetes API answers at $(sed -n 's/^ *server: //p' "$kc" | head -n 1)"
    server_external KUBERNETES || ( umask 077; cp "$kc" "$(k3s_dir)/kubeconfig-host.yaml" )
  else
    rm -f "$kc"
    die "The Kubernetes API does not answer with the kubeconfig."
  fi
  rm -f "$kc"
}

module_env() {
  local env
  pipeline_var DEPLOY_NAME "$(image_app_name)"
  pipeline_var DEPLOY_CONTAINER_PORT "$(value IMAGE_PORT 8080)"
  pipeline_var DEPLOY_HEALTH_PATH "$(value DEPLOY_HEALTH_PATH /actuator/health)"
  pipeline_var KUBERNETES_CHART "$(value KUBERNETES_CHART)"
  pipeline_var KUBERNETES_REPLICAS "$(value KUBERNETES_REPLICAS 2)"
  for env in $ENVIRONMENTS; do
    pipeline_var "KUBERNETES_$(upper "$env")_NODE_PORT" "$(value "KUBERNETES_$(upper "$env")_NODE_PORT")"
  done
  pipeline_secret KUBECONFIG_B64 "$(kubeconfig pipeline | base64 | tr -d '\n')"
}

module_stages() {
  # With Argo CD the pipeline commits to the GitOps branch instead.
  [[ " $MODULES " == *" gitops/"* ]] && return 0
  shell_stage 80 cd deploy-staging "sh \"\$DEVOPS_SCRIPTS/deploy-helm.sh\" staging"
  shell_stage 90 prod deploy-production "sh \"\$DEVOPS_SCRIPTS/deploy-helm.sh\" production"
}

# rollback [staging|production] [--to TAG]
module_rollback() {
  [[ " $MODULES " == *" gitops/"* ]] && return 0
  local env=production tag=''
  while (( $# )); do
    case $1 in
      staging|production) env=$1; shift ;;
      --to) tag=${2:?--to needs a tag}; shift 2 ;;
      *) die "rollback: unknown option $1 (use [staging|production] [--to TAG])" ;;
    esac
  done
  log_step "Rollback of $env${tag:+ to $tag}"
  (
    # shellcheck disable=SC1091
    source "$DEVOPS_ENV/pipeline.sh"
    export KUBECONFIG_B64
    KUBECONFIG_B64=$(kubeconfig host | base64 | tr -d '\n')
    sh "$DEVOPS_HOME/templates/scripts/deploy-helm.sh" "$env" rollback "$tag"
  ) || die "Rollback of $env failed"
  log_ok "$env is rolled back"
}

module_urls() {
  local env
  for env in $ENVIRONMENTS; do
    if server_external KUBERNETES; then
      printf '  %-12s namespace %s-%s%s\n' "${env^}" "$(image_app_name)" "$env" \
        "$(port=$(value "KUBERNETES_$(upper "$env")_NODE_PORT"); [[ -n $port ]] && printf ', node port %s' "$port")"
    else
      printf '  %-12s %s   (rollback: devops.sh rollback %s)\n' "${env^}" \
        "$(host_url "$(value "KUBERNETES_$(upper "$env")_PORT")")" "$env"
    fi
  done
  server_external KUBERNETES || printf '  %-12s export KUBECONFIG=%s/kubeconfig-host.yaml\n' Kubeconfig "$(k3s_dir)"
}
