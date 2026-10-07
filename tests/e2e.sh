#!/usr/bin/env bash
# End-to-end test: starts real tools in Docker, runs the whole pipeline of an
# example project and checks the results in the tools.
#
#   tests/e2e.sh <orchestrator> [modules]     e.g. tests/e2e.sh jenkins sonarqube,nexus
#
# The example is examples/hello-maven, or examples/hello-api when an image is
# built; E2E_EXAMPLE picks another one.
#
# Needs Docker with internet access; CI runs it on GitHub's runners
# (.github/workflows/e2e.yml).  The project is served from a local git
# repository over HTTP, so no GitHub repository or token is needed.
set -euo pipefail

ORCHESTRATOR=${1:?usage: tests/e2e.sh <maven|jenkins|concourse> [modules]}
WITH=${2:-sonarqube,nexus}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK=${E2E_WORK:-$(mktemp -d)}
mkdir -p "$WORK"
# An address the tool containers reach this machine on.
HOST_IP=${E2E_HOST_IP:-$(hostname -I | awk '{ print $1 }')}
GIT_PORT=${E2E_GIT_PORT:-8765}
case ,$WITH, in
  *,docker-registry,* | *,github-container,*) EXAMPLE=${E2E_EXAMPLE:-hello-api} ;;
  *) EXAMPLE=${E2E_EXAMPLE:-hello-maven} ;;
esac

project="$WORK/$EXAMPLE"
devops() { "$ROOT/devops.sh" -y -p "$project" "$@"; }
step() { printf '\n\033[1m### %s\033[0m\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

server_pid=''
cleanup() {
  local status=$?
  if (( status != 0 )); then
    step "Container logs (last lines)"
    devops compose ps || true
    devops compose logs --tail 80 || true
  fi
  [[ -n $server_pid ]] && kill "$server_pid" 2> /dev/null
  if [[ ${E2E_KEEP:-0} != 1 ]]; then
    devops compose down --volumes --remove-orphans > /dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup EXIT

step "Project and git server"
rm -rf "$project" "$WORK/git"
cp -R "$ROOT/examples/$EXAMPLE" "$project"
git -C "$project" init -q -b main
git -C "$project" add -A
git -C "$project" -c user.name=e2e -c user.email=e2e@example.com commit -qm "$EXAMPLE"
git clone -q --bare "$project" "$WORK/git/e2e/$EXAMPLE.git"
git -C "$WORK/git/e2e/$EXAMPLE.git" update-server-info
git -C "$project" remote add origin "http://$HOST_IP:$GIT_PORT/e2e/$EXAMPLE.git"
python3 -m http.server "$GIT_PORT" --bind 0.0.0.0 --directory "$WORK/git" > "$WORK/git-server.log" 2>&1 &
server_pid=$!
sleep 1
git ls-remote "http://$HOST_IP:$GIT_PORT/e2e/$EXAMPLE.git" > /dev/null || fail "git server not reachable"

step "devops.sh setup ($ORCHESTRATOR with $WITH)"
devops init --orchestrator "$ORCHESTRATOR" --with "$WITH" > /dev/null
# The committed team settings: a plain HTTP git server instead of GitHub.
cat >> "$project/devops.conf" <<EOF
GITHUB_URL=http://$HOST_IP:$GIT_PORT
GITHUB_REPOSITORY=e2e/$EXAMPLE
NEXUS_ACCEPT_EULA=yes
JENKINS_TRIGGER=none
TRIVY_FAIL_ON=
EOF
git config --global user.name > /dev/null 2>&1 || git config --global user.name e2e
git config --global user.email > /dev/null 2>&1 || git config --global user.email e2e@example.com
devops setup

if [[ ,$WITH, == *,jfrog,* ]]; then
  # Artifactory OSS cannot create repositories through its API, so the deploy
  # stage would need the Quick Setup wizard first; check the setup only.
  status=$(curl -s -o /dev/null -w '%{http_code}' -u "admin:$(devops get JFROG_ADMIN_PASSWORD)" \
    "http://localhost:$(devops get JFROG_HOST_PORT)/artifactory/api/repositories")
  [[ $status == 200 ]] || fail "Artifactory does not accept the new admin password (HTTP $status)"
  printf 'ok  Artifactory runs with the new admin password\n'
  printf '\nEnd-to-end test passed: setup of %s with %s (no run: Artifactory OSS repositories need Quick Setup)\n' "$ORCHESTRATOR" "$WITH"
  exit 0
fi

run_pipeline() {
  case $ORCHESTRATOR in
    maven|jenkins) devops run ;;
    concourse) devops run --phase ci && devops run --phase cd ;;
  esac
}

step "devops.sh run"
run_pipeline

step "Results in the tools"
if [[ ,$WITH, == *,sonarqube,* ]]; then
  measures=$(curl -fsS -u "$(devops get SONAR_TOKEN):" \
    "http://localhost:$(devops get SONAR_HOST_PORT)/api/measures/component?component=org.example:$EXAMPLE&metricKeys=ncloc")
  jq -e '.component.measures[0].value | tonumber > 0' <<< "$measures" > /dev/null || fail "SonarQube has no analysis: $measures"
  printf 'ok  SonarQube analysed %s\n' "$EXAMPLE"
fi
if [[ ,$WITH, == *,nexus,* ]]; then
  curl -fsS -o /dev/null -u "admin:$(devops get NEXUS_ADMIN_PASSWORD)" \
    "http://localhost:$(devops get NEXUS_HOST_PORT)/repository/maven-snapshots/org/example/$EXAMPLE/1.0.0-SNAPSHOT/maven-metadata.xml" \
    || fail "Nexus has no $EXAMPLE snapshot"
  printf 'ok  Nexus has the snapshot\n'
fi
if [[ ,$WITH, == *,docker-registry,* ]]; then
  tag=$(git -C "$project" rev-parse --short=12 HEAD)
  tags=$(curl -fsS "http://localhost:$(devops get REGISTRY_HOST_PORT)/v2/$(devops get IMAGE_NAME)/tags/list")
  jq -e --arg tag "$tag" '.tags | index($tag) and index("latest")' <<< "$tags" > /dev/null \
    || fail "the registry has no image tagged $tag and latest: $tags"
  docker pull -q "localhost:$(devops get REGISTRY_HOST_PORT)/$(devops get IMAGE_NAME):$tag" > /dev/null
  docker run -d --name e2e-image -p 18080:8080 "localhost:$(devops get REGISTRY_HOST_PORT)/$(devops get IMAGE_NAME):$tag" > /dev/null
  for _ in $(seq 60); do curl -fsS -o /dev/null http://localhost:18080/actuator/health 2> /dev/null && break; sleep 2; done
  health=$(curl -fsS http://localhost:18080/actuator/health || true)
  docker rm -f e2e-image > /dev/null
  [[ $health == *UP* ]] || fail "the image does not start: $health"
  printf 'ok  the registry has the image %s and it starts\n' "$tag"
fi
if [[ ,$WITH, == *,syft,* && $ORCHESTRATOR == maven ]]; then
  jq -e '.packages | length > 10' "$project/target/sbom.spdx.json" > /dev/null || fail "no SBOM in target/sbom.spdx.json"
  printf 'ok  SBOM with %s packages\n' "$(jq '.packages | length' "$project/target/sbom.spdx.json")"
fi
if [[ ,$WITH, == *,trivy,* && $ORCHESTRATOR == maven ]]; then
  jq -e '.ArtifactName' "$project/target/trivy-report.json" > /dev/null || fail "no Trivy report"
  printf 'ok  Trivy report of %s\n' "$(jq -r .ArtifactName "$project/target/trivy-report.json")"
fi
if [[ ,$WITH, == *,cosign,* ]]; then
  cosign=$(sh "$ROOT/templates/scripts/tool.sh" cosign)
  image="localhost:$(devops get REGISTRY_HOST_PORT)/$(devops get IMAGE_NAME):$(git -C "$project" rev-parse --short=12 HEAD)"
  "$cosign" verify --key "$project/.devops/keys/cosign.pub" --insecure-ignore-tlog=true --allow-http-registry \
    "$image" > /dev/null 2>&1 || fail "$image has no signature of the project key"
  if [[ ,$WITH, == *,syft,* ]]; then
    "$cosign" verify-attestation --key "$project/.devops/keys/cosign.pub" --insecure-ignore-tlog=true \
      --allow-http-registry --type spdxjson "$image" > /dev/null 2>&1 || fail "$image has no SBOM attestation"
  fi
  printf 'ok  %s is signed\n' "$image"
fi
if [[ ,$WITH, == *,docker-host,* || ,$WITH, == *,kubernetes,* ]]; then
  # app_check <environment>: prints the tag that runs and checks the answer.
  app_check() {
    local env_upper port answer image
    env_upper=$(tr '[:lower:]' '[:upper:]' <<< "$1")
    if [[ ,$WITH, == *,kubernetes,* ]]; then
      port=$(devops get "KUBERNETES_${env_upper}_PORT")
      image=$(devops compose exec -T k3s kubectl get deployment "$(devops get IMAGE_NAME)" \
        --namespace "$(devops get IMAGE_NAME)-$1" --output 'jsonpath={.spec.template.spec.containers[0].image}')
    else
      port=$(devops get "DEPLOY_${env_upper}_PORT")
      image=$(docker inspect --format '{{.Config.Image}}' "$(devops get IMAGE_NAME)-$1-app-1")
    fi
    answer=$(curl -fsS "http://localhost:$port/hello?name=e2e") || fail "$1 does not answer on port $port"
    jq -e --arg env "$1" '.environment == $env' <<< "$answer" > /dev/null || fail "$1 answers $answer"
    printf '%s\n' "${image##*:}"
  }
  prod_port=$(devops get DEPLOY_PRODUCTION_PORT 2> /dev/null || devops get KUBERNETES_PRODUCTION_PORT)
  first=$(git -C "$project" rev-parse --short=12 HEAD)
  [[ $(app_check staging) == "$first" ]] || fail "staging does not run $first"
  printf 'ok  staging runs %s\n' "$first"
  ! curl -fsS -o /dev/null "http://localhost:$prod_port/actuator/health" 2> /dev/null \
    || fail "production was deployed without approval"
  printf 'ok  production waits for the approval\n'

  step "devops.sh run --phase prod"
  devops run --phase prod
  [[ $(app_check production) == "$first" ]] || fail "production does not run $first"
  printf 'ok  production runs %s\n' "$first"

  step "A second commit, then rollback"
  printf '\nChanged by the end-to-end test.\n' >> "$project/README.md"
  git -C "$project" commit -qam "Second commit"
  git -C "$project" push -q "$WORK/git/e2e/$EXAMPLE.git" main
  git -C "$WORK/git/e2e/$EXAMPLE.git" update-server-info
  second=$(git -C "$project" rev-parse --short=12 HEAD)
  run_pipeline
  devops run --phase prod
  [[ $(app_check production) == "$second" ]] || fail "production does not run $second"
  printf 'ok  production runs %s\n' "$second"
  devops rollback production
  [[ $(app_check production) == "$first" ]] || fail "rollback did not bring back $first"
  printf 'ok  rollback brought back %s\n' "$first"
fi
printf '\nEnd-to-end test passed: %s with %s\n' "$ORCHESTRATOR" "$WITH"
