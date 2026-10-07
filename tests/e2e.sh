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
  *,docker-registry,*) EXAMPLE=${E2E_EXAMPLE:-hello-api} ;;
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

step "devops.sh run"
case $ORCHESTRATOR in
  maven) devops run ;;
  jenkins) devops run ;;
  concourse) devops run --phase ci && devops run --phase cd ;;
esac

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
printf '\nEnd-to-end test passed: %s with %s\n' "$ORCHESTRATOR" "$WITH"
