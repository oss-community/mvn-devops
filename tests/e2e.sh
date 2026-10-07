#!/usr/bin/env bash
# End-to-end test: starts real tools in Docker, runs the whole pipeline of
# examples/hello-maven and checks the results in the tools.
#
#   tests/e2e.sh <orchestrator> [modules]     e.g. tests/e2e.sh jenkins sonarqube,nexus
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

project="$WORK/hello-maven"
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
cp -R "$ROOT/examples/hello-maven" "$project"
git -C "$project" init -q -b main
git -C "$project" add -A
git -C "$project" -c user.name=e2e -c user.email=e2e@example.com commit -qm "hello-maven"
git clone -q --bare "$project" "$WORK/git/e2e/hello-maven.git"
git -C "$WORK/git/e2e/hello-maven.git" update-server-info
git -C "$project" remote add origin "http://$HOST_IP:$GIT_PORT/e2e/hello-maven.git"
python3 -m http.server "$GIT_PORT" --bind 0.0.0.0 --directory "$WORK/git" > "$WORK/git-server.log" 2>&1 &
server_pid=$!
sleep 1
git ls-remote "http://$HOST_IP:$GIT_PORT/e2e/hello-maven.git" > /dev/null || fail "git server not reachable"

step "devops.sh setup ($ORCHESTRATOR with $WITH)"
devops init --orchestrator "$ORCHESTRATOR" --with "$WITH" > /dev/null
# The committed team settings: a plain HTTP git server instead of GitHub.
cat >> "$project/devops.conf" <<EOF
GITHUB_URL=http://$HOST_IP:$GIT_PORT
GITHUB_REPOSITORY=e2e/hello-maven
NEXUS_ACCEPT_EULA=yes
EOF
git config --global user.name > /dev/null 2>&1 || git config --global user.name e2e
git config --global user.email > /dev/null 2>&1 || git config --global user.email e2e@example.com
devops setup

step "devops.sh run"
case $ORCHESTRATOR in
  maven) devops run ;;
  jenkins) devops run ;;
  concourse) devops run --phase ci && devops run --phase cd ;;
esac

step "Results in the tools"
pipeline_env=$(devops env --show)
if [[ ,$WITH, == *,sonarqube,* ]]; then
  measures=$(curl -fsS -u "$(devops get SONAR_TOKEN):" \
    "http://localhost:$(devops get SONAR_HOST_PORT)/api/measures/component?component=org.example:hello-maven&metricKeys=ncloc")
  jq -e '.component.measures[0].value | tonumber > 0' <<< "$measures" > /dev/null || fail "SonarQube has no analysis: $measures"
  printf 'ok  SonarQube analysed hello-maven\n'
fi
if [[ ,$WITH, == *,nexus,* ]]; then
  curl -fsS -o /dev/null -u "admin:$(devops get NEXUS_ADMIN_PASSWORD)" \
    "http://localhost:$(devops get NEXUS_HOST_PORT)/repository/maven-snapshots/org/example/hello-maven/1.0.0-SNAPSHOT/maven-metadata.xml" \
    || fail "Nexus has no hello-maven snapshot"
  printf 'ok  Nexus has the snapshot\n'
fi
if [[ ,$WITH, == *,jfrog,* ]]; then
  url=$(grep '^JFROG_ARTIFACTORY_SNAPSHOT_URL=' <<< "$pipeline_env" | cut -d= -f2-)
  url=${url/jfrog:8082/localhost:$(devops get JFROG_HOST_PORT)}
  curl -fsS -o /dev/null -u "admin:$(devops get JFROG_ADMIN_PASSWORD)" "${url}org/example/hello-maven/1.0.0-SNAPSHOT/maven-metadata.xml" \
    || fail "Artifactory has no hello-maven snapshot under $url"
  printf 'ok  Artifactory has the snapshot\n'
fi
printf '\nEnd-to-end test passed: %s with %s\n' "$ORCHESTRATOR" "$WITH"
