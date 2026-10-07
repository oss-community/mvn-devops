# shellcheck shell=bash
# Container images, shared by the modules of the "image" category.
#
# A registry module asks image_secrets, exports image_env with the repository
# the pipeline pushes to, and adds image_stages.  The image is built with Jib
# by default: no Docker daemon and no Dockerfile are needed, so it works in
# every orchestrator.  A project's own Dockerfile is used instead with
# IMAGE_BUILDER=dockerfile, which needs Docker where the pipeline runs (the
# maven orchestrator).
#
# Every image gets two tags: the commit (git rev-parse --short=12 HEAD), which
# never changes and is what deployments use, and "latest" for people.

mvn_jib() { mvn_plugin MVN_JIB_VERSION com.google.cloud.tools:jib-maven-plugin 3.5.2 build; }

# The tag deployments use; evaluated where the pipeline runs.
IMAGE_TAG_EXPR='$(git rev-parse --short=12 HEAD)'

image_secrets() {
  local name builder=jib
  name=$(printf '%s' "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
  ask IMAGE_NAME "Image name" "$name"
  ask IMAGE_MODULE "Maven module of the application (empty: the root project)" ""
  [[ -f "$PROJECT_DIR/Dockerfile" && ${DEVOPS_RUNS_IN:-host} == host ]] && builder=dockerfile
  ask IMAGE_BUILDER "Build the image with jib or with the project's dockerfile" "$builder"
  if [[ $(value IMAGE_BUILDER jib) == jib ]]; then
    ask IMAGE_BASE "Base image" "eclipse-temurin:$(value JAVA_VERSION 21)-jre"
  fi
  ask IMAGE_PORT "Port the application listens on in the container" 8080
}

# image_env <push repository> <deploy repository> [user] [password]
#   push repository    where the pipeline pushes, as the pipeline reaches the registry
#   deploy repository  the same image as the machines that run it pull it
image_env() {
  pipeline_var IMAGE_REPOSITORY "$1"
  pipeline_var IMAGE_DEPLOY_REPOSITORY "$2"
  pipeline_var IMAGE_REGISTRY_USERNAME "${3:-}"
  pipeline_secret IMAGE_REGISTRY_PASSWORD "${4:-}"
}

# image_stages <insecure> <auth>: insecure=1 for a registry without TLS,
# auth=1 when the registry needs IMAGE_REGISTRY_USERNAME and _PASSWORD.
image_stages() {
  local insecure=${1:-0} auth=${2:-1} args module
  module=$(value IMAGE_MODULE)
  if [[ $(value IMAGE_BUILDER jib) == dockerfile ]]; then
    [[ ${DEVOPS_RUNS_IN:-host} == host ]] \
      || die "IMAGE_BUILDER=dockerfile needs Docker where the pipeline runs; use jib with $ORCHESTRATOR."
    shell_stage 75 cd image "bash \"\$DEVOPS_SCRIPTS/image-dockerfile.sh\"${module:+ $module}"
    return
  fi
  args="package -DskipTests=true"
  [[ -n $module ]] && args+=" -pl $module"
  args+=" $(mvn_jib) -Djib.from.image=$(value IMAGE_BASE eclipse-temurin:21-jre)"
  args+=" -Djib.to.image=\$IMAGE_REPOSITORY:$IMAGE_TAG_EXPR -Djib.to.tags=latest"
  (( auth )) && args+=" -Djib.to.auth.username=\$IMAGE_REGISTRY_USERNAME -Djib.to.auth.password=\$IMAGE_REGISTRY_PASSWORD"
  args+=" -Djib.container.ports=$(value IMAGE_PORT 8080) -Djib.container.creationTime=USE_CURRENT_TIMESTAMP"
  (( insecure )) && args+=" -Djib.allowInsecureRegistries=true -DsendCredentialsOverHttp=true"
  stage 75 cd image "$args"
}
