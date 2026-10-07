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
# sed -i differs between GNU and BSD (macOS) sed.
sed_i() { sed "$1" "$2" > "$2.tmp" && mv "$2.tmp" "$2"; }

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
# The server URLs come from the committed devops.conf.
rm -rf "$project/.devops" "$project/devops.conf"
devops init --orchestrator jenkins --with sonarqube,nexus,jfrog,github-packages,github-pages > /dev/null
cat >> "$project/devops.conf" <<'EOF'
GITHUB_URL=https://ghe.acme.test
SONAR_SERVER_URL=https://sonar.acme.test/
NEXUS_SERVER_URL=https://nexus.acme.test
JFROG_SERVER_URL=https://acme.jfrog.test/artifactory
JENKINS_SERVER_URL=https://jenkins.acme.test
EOF
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

# devops.conf: the team's answers are committed, secrets and personal values are not.
rm -rf "$project/.devops" "$project/devops.conf"
devops init --orchestrator maven --with sonarqube,nexus > /dev/null
devops secrets > /dev/null
conf="$project/devops.conf"
grep -qx 'ORCHESTRATOR=maven' "$conf" || fail "devops.conf: orchestrator missing"
grep -qx 'NEXUS_HOST_PORT=8084' "$conf" || fail "devops.conf: shared answer missing"
! grep -qE '^(DEVOPS_HOST|GITHUB_USERNAME|GITHUB_EMAIL)=' "$conf" || fail "devops.conf: personal value shared"
! grep -qE '^[A-Z_]*(PASSWORD|TOKEN)=' "$conf" || fail "devops.conf: secret shared"
sed_i 's/^NEXUS_HOST_PORT=.*/NEXUS_HOST_PORT=9184/' "$conf"
rm -rf "$project/.devops"   # a fresh clone: no local state, no init
devops secrets > /dev/null
[[ $(devops get NEXUS_HOST_PORT) == 9184 ]] || fail "devops.conf: answer not used on a fresh clone"
env_out=$(devops env --show)
grep -q '^NEXUS_ARTIFACTORY_HOST_URL=http://localhost:9184$' <<< "$env_out" || fail "devops.conf: answer not in the pipeline"
# A project set up with 1.0.0 keeps working: profile.conf moves to devops.conf.
rm -f "$conf"
printf "PROJECT_NAME=demo-app\nORCHESTRATOR=maven\nMODULES='scm/github build/maven orchestrator/maven'\n" > "$project/.devops/profile.conf"
devops stages > /dev/null
grep -qx 'MODULES=scm/github build/maven orchestrator/maven' "$conf" || fail "devops.conf: profile.conf not moved"
[[ ! -f "$project/.devops/profile.conf" ]] || fail "devops.conf: profile.conf left behind"
printf 'ok  devops.conf\n'

# Container image: Jib in every orchestrator, the helper scripts reach CI.
for orchestrator in maven jenkins concourse; do
  rm -rf "$project/.devops" "$project/devops.conf"
  devops init --orchestrator "$orchestrator" --with docker-registry > /dev/null
  devops secrets > /dev/null
  stages=$(devops stages)
  grep -q ' image ' <<< "$stages" || fail "image: $orchestrator has no image stage"
  grep -q 'jib-maven-plugin' <<< "$stages" || fail "image: $orchestrator does not build with Jib"
  devops render > /dev/null
  env_out=$(devops env --show)
  grep -q '^IMAGE_DEPLOY_REPOSITORY=localhost:5000/demo-app$' <<< "$env_out" || fail "image: $orchestrator deploy repository"
  case $orchestrator in
    maven) grep -q "^DEVOPS_SCRIPTS=$ROOT/templates/scripts$" <<< "$env_out" || fail "image: maven DEVOPS_SCRIPTS" ;;
    jenkins) grep -q '\.devops/scripts/image-dockerfile\.sh' "$project/.devops/generated/Jenkinsfile" || fail "image: jenkins scripts" ;;
    concourse) grep -q '\.devops/scripts/image-dockerfile\.sh' "$project/.devops/generated/concourse/pipeline.yml" || fail "image: concourse scripts" ;;
  esac
done
# A Dockerfile is built with Docker where the pipeline runs on this machine.
touch "$project/Dockerfile"
rm -rf "$project/.devops" "$project/devops.conf"
devops init --orchestrator maven --with docker-registry > /dev/null
devops secrets > /dev/null
devops stages | grep -q 'image-dockerfile.sh' || fail "image: Dockerfile not used"
rm -f "$project/Dockerfile"
printf 'ok  image\n'

# release: next development version
# shellcheck source=../lib/release.sh
source "$ROOT/lib/release.sh"
for pair in 1.2.0:1.2.1-SNAPSHOT 1.9:1.10-SNAPSHOT 2.0.0-RC1:2.0.0-RC2-SNAPSHOT 3:4-SNAPSHOT; do
  [[ $(next_snapshot "${pair%%:*}") == "${pair#*:}" ]] || fail "release: next_snapshot ${pair%%:*}"
done
printf 'ok  release versions\n'

# Line endings: mvn-devops committed into a project stays LF even when the
# project is cloned with core.autocrlf=true (git on Windows), and doctor reports CRLF.
crlf_dir="$WORK/crlf"
mkdir -p "$crlf_dir/app/mvn-devops"
cp -R "$ROOT"/{.gitattributes,devops.sh,devops.bat,lib,modules,templates,VERSION} "$crlf_dir/app/mvn-devops/"
git -C "$crlf_dir/app" init -q
git -C "$crlf_dir/app" add -A
git -C "$crlf_dir/app" -c user.name=t -c user.email=t@t commit -qm init
git -c core.autocrlf=true clone -q "$crlf_dir/app" "$crlf_dir/clone"
! grep -rlIU $'\r' --exclude='*.bat' "$crlf_dir/clone/mvn-devops" > /dev/null || fail "line endings: CRLF after autocrlf checkout"
grep -qU $'\r' "$crlf_dir/clone/mvn-devops/devops.bat" || fail "line endings: devops.bat should be CRLF"
perl -pi -e 's/\n/\r\n/' "$crlf_dir/clone/mvn-devops/templates/settings.xml"
doctor_out=$("$crlf_dir/clone/mvn-devops/devops.sh" doctor 2>&1 || true)
grep -q "CRLF" <<< "$doctor_out" || fail "line endings: doctor should report CRLF"
eval "$(grep 'doctor --fix' <<< "$doctor_out")" > /dev/null
doctor_out=$("$crlf_dir/clone/mvn-devops/devops.sh" doctor 2>&1 || true)
grep -q "line endings (LF)" <<< "$doctor_out" || fail "line endings: the fix doctor prints does not work:
$doctor_out"
printf 'ok  line endings\n'

# upgrade: a copy inside a project is replaced by a checked release.
if command -v zip > /dev/null; then
  releases="$WORK/releases/download/v9.9.9"
  mkdir -p "$releases"
  NFPM=true DIST="$WORK/dist" "$ROOT/packaging/build.sh" 9.9.9 > /dev/null
  cp "$WORK/dist/mvn-devops-9.9.9.tar.gz" "$WORK/dist/SHA256SUMS" "$releases/"
  copy="$WORK/app/mvn-devops"
  mkdir -p "$copy"
  cp -R "$ROOT"/{devops.sh,lib,modules,templates,VERSION} "$copy/"
  touch "$copy/lib/removed-in-new-release.sh"
  DEVOPS_RELEASES_URL="file://$WORK/releases" "$copy/devops.sh" upgrade --version 9.9.9 > /dev/null
  [[ $(cat "$copy/VERSION") == 9.9.9 ]] || fail "upgrade: VERSION not replaced"
  [[ ! -e "$copy/lib/removed-in-new-release.sh" ]] || fail "upgrade: old files left behind"
  printf 'x' >> "$releases/mvn-devops-9.9.9.tar.gz"
  printf '1.0.0' > "$copy/VERSION"
  ! DEVOPS_RELEASES_URL="file://$WORK/releases" "$copy/devops.sh" upgrade --version 9.9.9 > /dev/null 2>&1 \
    || fail "upgrade: a bad checksum must fail"
  [[ $(cat "$copy/VERSION") == 1.0.0 ]] || fail "upgrade: changed files despite a bad checksum"
  printf 'ok  upgrade\n'
fi

printf 'All smoke tests passed\n'
