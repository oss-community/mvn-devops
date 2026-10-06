#!/usr/bin/env bash
# Smoke test: every orchestrator can be selected, configured with defaults and
# rendered, without Docker.  Run: tests/smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

project="$WORK/demo-app"
mkdir -p "$project"
git -C "$project" init -q -b main
git -C "$project" remote add origin git@github.com:example/demo-app.git
printf '<project/>\n' > "$project/pom.xml"
printf '<settings/>\n' > "$project/settings.xml"

devops() { "$ROOT/devops.sh" -y -p "$project" "$@"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for orchestrator in maven jenkins concourse; do
  rm -rf "$project/.devops"
  devops init --orchestrator "$orchestrator" --with sonarqube,nexus,jfrog,github-packages,github-pages > /dev/null
  devops secrets > /dev/null
  [[ $(devops get GITHUB_REPOSITORY) == example/demo-app ]] || fail "repository not detected"
  stages=$(devops stages)
  for name in validate build test checkstyle sonar install site stage-site publish-site deploy-jfrog deploy-github deploy-nexus; do
    grep -q " $name " <<< "$stages" || fail "$orchestrator: stage $name missing"
  done
  devops render > /dev/null
  env_out=$(devops env --show)
  grep -q '^NEXUS_ARTIFACTORY_PASSWORD=\*\*\*\*\*\*\*\*$' <<< "$env_out" || fail "secrets are not masked"
  case $orchestrator in
    maven)
      [[ -x "$project/.devops/generated/pipeline.sh" ]] || fail "maven: pipeline.sh missing"
      grep -q '^SONAR_URL=http://localhost:9000$' <<< "$env_out" || fail "maven: SONAR_URL should use localhost"
      devops run --dry-run > /dev/null ;;
    jenkins)
      grep -q "credentials('SONAR_TOKEN')" "$project/.devops/generated/Jenkinsfile" || fail "jenkins: credential missing"
      grep -q "pipelineJob('demo-app')" "$project/.devops/generated/jenkins/casc.yaml" || fail "jenkins: job missing"
      grep -q "pollSCM('H/2 \* \* \* \*')" "$project/.devops/generated/Jenkinsfile" || fail "jenkins: poll trigger missing"
      grep -q '^SONAR_URL=http://sonarqube:9000$' <<< "$env_out" || fail "jenkins: SONAR_URL should use the service name" ;;
    concourse)
      grep -q 'passed: \[ci\]' "$project/.devops/generated/concourse/pipeline.yml" || fail "concourse: cd job missing"
      grep -q '^SONAR_TOKEN:' "$project/.devops/generated/concourse/vars.yml" || fail "concourse: vars missing"
      grep -q "tag: '3.9-eclipse-temurin-21'" "$project/.devops/generated/concourse/pipeline.yml" || fail "concourse: build image should be Maven 3.9, Java 21" ;;
  esac
  if command -v docker > /dev/null && docker compose version > /dev/null 2>&1; then
    devops compose config -q || fail "$orchestrator: compose config is invalid"
    devops export-compose > /dev/null
    ( cd "$project/.devops/compose" && docker compose config -q ) || fail "$orchestrator: exported compose is invalid"
    grep -q 'PASSWORD: \${' "$project/.devops/compose/docker-compose.yml" || fail "$orchestrator: exported compose should keep \${VARS}"
  fi
  printf 'ok  %s\n' "$orchestrator"
done
# Every tool on an existing server, GitHub Enterprise: no containers at all.
rm -rf "$project/.devops"
devops init --orchestrator jenkins --with sonarqube,nexus,jfrog,github-packages,github-pages > /dev/null
values="$project/.devops/values"
mkdir -p "$values"
printf '%s' https://ghe.acme.test > "$values/GITHUB_URL"
printf '%s' https://sonar.acme.test/ > "$values/SONAR_SERVER_URL"
printf '%s' https://nexus.acme.test > "$values/NEXUS_SERVER_URL"
printf '%s' https://acme.jfrog.test/artifactory > "$values/JFROG_SERVER_URL"
printf '%s' https://jenkins.acme.test > "$values/JENKINS_SERVER_URL"
devops secrets > /dev/null
devops render > /dev/null
env_out=$(devops env --show)
for expected in SONAR_URL=https://sonar.acme.test \
    NEXUS_ARTIFACTORY_SNAPSHOT_URL=https://nexus.acme.test/repository/maven-snapshots/ \
    JFROG_ARTIFACTORY_RELEASE_URL=https://acme.jfrog.test/artifactory/demo-libs-release-local/ \
    GITHUB_PACKAGES_URL=https://maven.ghe.acme.test/example/demo-app \
    GITHUB_HOST=ghe.acme.test; do
  grep -qx "$expected" <<< "$env_out" || fail "existing servers: $expected missing"
done
jenkinsfile="$project/.devops/generated/Jenkinsfile"
grep -q "SONAR_TOKEN = credentials('demo-app-SONAR_TOKEN')" "$jenkinsfile" || fail "existing jenkins: credential id"
grep -q "SONAR_URL = 'https://sonar.acme.test'" "$jenkinsfile" || fail "existing jenkins: plain variables"
grep -q "credentialsId: 'demo-app-github-https'" "$jenkinsfile" || fail "existing jenkins: checkout credential"
devops compose config --services 2>&1 | grep -q "No selected module needs containers" || fail "existing servers: no container expected"
printf 'ok  existing servers\n'

# release: next development version
# shellcheck source=../lib/release.sh
source "$ROOT/lib/release.sh"
for pair in 1.2.0:1.2.1-SNAPSHOT 1.9:1.10-SNAPSHOT 2.0.0-RC1:2.0.0-RC2-SNAPSHOT 3:4-SNAPSHOT; do
  [[ $(next_snapshot "${pair%%:*}") == "${pair#*:}" ]] || fail "release: next_snapshot ${pair%%:*}"
done
printf 'ok  release versions\n'

printf 'All smoke tests passed\n'
