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
      grep -q '^SONAR_URL=http://sonarqube:9000$' <<< "$env_out" || fail "jenkins: SONAR_URL should use the service name" ;;
    concourse)
      grep -q 'passed: \[ci\]' "$project/.devops/generated/concourse/pipeline.yml" || fail "concourse: cd job missing"
      grep -q '^SONAR_TOKEN:' "$project/.devops/generated/concourse/vars.yml" || fail "concourse: vars missing" ;;
  esac
  if command -v docker > /dev/null && docker compose version > /dev/null 2>&1; then
    devops compose config -q || fail "$orchestrator: compose config is invalid"
  fi
  printf 'ok  %s\n' "$orchestrator"
done
printf 'All smoke tests passed\n'
