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
    jenkins) grep -q 'base64 -d | tar -xzf - -C .devops' "$project/.devops/generated/Jenkinsfile" || fail "image: jenkins scripts" ;;
    concourse) grep -q 'base64 -d | tar -xzf - -C .devops' "$project/.devops/generated/concourse/pipeline.yml" || fail "image: concourse scripts" ;;
  esac
done
# Deployment: staging, then production behind an approval.
for orchestrator in maven jenkins concourse; do
  rm -rf "$project/.devops" "$project/devops.conf"
  devops init --orchestrator "$orchestrator" --with docker-registry,docker-host > /dev/null
  devops secrets > /dev/null
  stages=$(devops stages)
  grep -q '^80 *staging *deploy-staging ' <<< "$stages" || fail "deploy: $orchestrator has no staging stage"
  grep -q '^- *production *approval ' <<< "$stages" || fail "deploy: $orchestrator production needs no approval"
  grep -q '^80 *production *deploy-production ' <<< "$stages" || fail "deploy: $orchestrator has no production stage"
  devops render > /dev/null
  case $orchestrator in
    maven)
      run_out=$(devops run --dry-run 2>&1)
      grep -q 'deploy-staging' <<< "$run_out" || fail "deploy: maven does not deploy to staging"
      ! grep -q '\] deploy-production' <<< "$run_out" || fail "deploy: maven deploys to production without approval"
      run_out=$(devops run --dry-run --phase prod 2>&1)
      grep -q 'deploy-production' <<< "$run_out" || fail "deploy: maven --phase prod" ;;
    jenkins)
      jenkinsfile="$project/.devops/generated/Jenkinsfile"
      grep -q "input id: 'Production', message: 'Deploy to production?'" "$jenkinsfile" || fail "deploy: jenkins has no approval"
      [[ $(grep -n "approve-production" "$jenkinsfile" | cut -d: -f1) -lt $(grep -n "stage('deploy-production')" "$jenkinsfile" | cut -d: -f1) ]] \
        || fail "deploy: jenkins approval is not before production" ;;
    concourse)
      grep -q 'name: production' "$project/.devops/generated/concourse/pipeline.yml" || fail "deploy: concourse has no production job"
      grep -q 'passed: \[cd\]' "$project/.devops/generated/concourse/pipeline.yml" || fail "deploy: concourse production job does not follow cd" ;;
  esac
  [[ $(devops env --show | grep '^DEPLOY_STAGING_TARGET=') == "DEPLOY_STAGING_TARGET=root@$( [[ $orchestrator == maven ]] && echo localhost || echo deploy-host)" ]] \
    || fail "deploy: $orchestrator reaches the simulated machine at the wrong address"
done
# Kubernetes: the same stages with Helm; the pipeline reaches k3s by its service name.
for orchestrator in maven jenkins; do
  rm -rf "$project/.devops" "$project/devops.conf"
  devops init --orchestrator "$orchestrator" --with docker-registry,kubernetes > /dev/null
  devops secrets > /dev/null
  stages=$(devops stages)
  grep -q 'deploy-helm.sh" staging' <<< "$stages" || fail "kubernetes: $orchestrator has no staging stage"
  grep -q '^80 *production *deploy-production .*deploy-helm.sh" production' <<< "$stages" || fail "kubernetes: $orchestrator production"
  mkdir -p "$project/.devops/k3s"
  printf 'apiVersion: v1\nclusters:\n- cluster:\n    server: https://127.0.0.1:6443\n' > "$project/.devops/k3s/kubeconfig.yaml"
  server=$(devops env --show > /dev/null; base64 -d < <(sed -n 's/^export KUBECONFIG_B64=//p' "$project/.devops/env/pipeline.sh" | tr -d "'") | sed -n 's/ *server: //p')
  expected=https://localhost:6443; [[ $orchestrator == jenkins ]] && expected=https://k3s:6443
  [[ $server == "$expected" ]] || fail "kubernetes: $orchestrator reaches the API at '$server'"
done
# Argo CD brings the kubernetes module and replaces its Helm stages.
rm -rf "$project/.devops" "$project/devops.conf"
devops init --orchestrator concourse --with docker-registry,argocd > /dev/null
grep -q 'deploy/kubernetes' "$project/devops.conf" || fail "argocd: kubernetes module not added"
devops secrets > /dev/null
stages=$(devops stages)
grep -q 'deploy-gitops.sh" staging' <<< "$stages" || fail "argocd: no GitOps staging stage"
! grep -q 'deploy-helm.sh' <<< "$stages" || fail "argocd: Helm stages still there"
[[ $(grep -c ' deploy-' <<< "$stages") == 2 ]] || fail "argocd: expected two deploy stages"
printf 'ok  kubernetes\n'
! devops init --orchestrator maven --with docker-host,kubernetes > /dev/null 2>&1 || fail "deploy: two deployment modules accepted"
! devops init --orchestrator maven --with docker-registry,github-container > /dev/null 2>&1 || fail "image: two image modules accepted"
rm -rf "$project/.devops" "$project/devops.conf"
devops init --orchestrator maven --with docker-host > /dev/null
! devops secrets > /dev/null 2>&1 || fail "deploy: accepted without an image module"
printf 'ok  deploy\n'

# Environments of the project's own: dev test staging prod, with approvals
# before staging and prod.  Ports count up from the last environment.
rm -rf "$project/.devops" "$project/devops.conf"
devops init --orchestrator maven --with docker-registry,kubernetes,cosign,k6,postgresql > /dev/null
printf 'ENVIRONMENTS=dev test staging prod\nENV_STAGING_APPROVAL=yes\n' >> "$project/devops.conf"
mkdir -p "$project/.devops/values" && printf '%s' "$WORK/cosign.key" > "$project/.devops/values/COSIGN_KEY_FILE"
printf 'unused' > "$WORK/cosign.key"; printf 'unused' > "$WORK/cosign.pub"
devops secrets > /dev/null
stages=$(devops stages | awk 'NR > 1 { print $2 ":" $3 }' | tr '\n' ' ')
[[ $stages == *"cd:sign-image dev:deploy-dev test:deploy-test staging:approval staging:verify-image-staging staging:deploy-staging staging:load-test prod:approval prod:verify-image-prod prod:deploy-prod "* ]] \
  || fail "environments: stages $stages"
run_out=$(devops run --dry-run 2>&1)
grep -q '\] deploy-test' <<< "$run_out" || fail "environments: test is not deployed"
! grep -q '\] deploy-staging' <<< "$run_out" || fail "environments: staging deployed without approval"
grep -q "staging waits for approval" <<< "$run_out" || fail "environments: no hint at the staging approval"
run_out=$(devops run --dry-run --phase staging 2>&1)
grep -q '\] load-test' <<< "$run_out" || fail "environments: --phase staging does not load test"
! grep -q '\] deploy-prod' <<< "$run_out" || fail "environments: --phase staging deploys prod"
grep -q "prod waits for approval" <<< "$run_out" || fail "environments: no hint at the prod approval"
run_out=$(devops run --dry-run --phase production 2>&1)
grep -q '\] deploy-prod' <<< "$run_out" || fail "environments: production does not stand for prod"
env_out=$(devops env --show)
grep -qx 'ENVIRONMENTS=dev test staging prod' <<< "$env_out" || fail "environments: not in the pipeline"
grep -q '^DATABASE_DEV_PASSWORD=\*' <<< "$env_out" || fail "environments: dev has no database password"
[[ $(devops get KUBERNETES_DEV_PORT):$(devops get KUBERNETES_PROD_PORT) == 8283:8280 ]] || fail "environments: ports"
# "up" with a docker that does nothing writes the configuration.
mkdir -p "$WORK/fake-bin" && printf '#!/bin/sh\nexit 0\n' > "$WORK/fake-bin/docker" && chmod +x "$WORK/fake-bin/docker"
PATH="$WORK/fake-bin:$PATH" devops up > /dev/null
grep -q '"8283:30083"' "$project/.devops/generated/compose/deploy-kubernetes.yml" || fail "environments: k3s does not publish dev"
grep -qx 'LOAD_TEST_ENVIRONMENT=staging' "$project/devops.conf" || fail "environments: load test not before the last"
printf 'ENVIRONMENTS=dev Test\n' >> "$project/devops.conf"
! devops secrets > /dev/null 2>&1 || fail "environments: invalid name accepted"
printf 'ok  environments\n'

# Image security: SBOM, scan and signature after the image, verification before production.
rm -rf "$project/.devops" "$project/devops.conf"
devops init --orchestrator concourse --with docker-registry,docker-host,trivy,syft,cosign > /dev/null
mkdir -p "$project/.devops/values" && printf '%s' "$WORK/cosign.key" > "$project/.devops/values/COSIGN_KEY_FILE"
printf 'unused' > "$WORK/cosign.key"; printf 'unused' > "$WORK/cosign.pub"
devops secrets > /dev/null
stages=$(devops stages | awk 'NR > 1 { print $1 ":" $3 }' | tr '\n' ' ')
[[ $stages == *"75:image 76:sbom 77:scan-image 78:sign-image 80:deploy-staging -:approval 79:verify-image-production 80:deploy-production "* ]] \
  || fail "security: stage order $stages"
devops render > /dev/null
grep -q 'path: .tools' "$project/.devops/generated/concourse/pipeline.yml" || fail "security: concourse does not cache tools"
env_out=$(devops env --show)
grep -q '^COSIGN_KEY_B64=\*\*\*\*\*\*\*\*$' <<< "$env_out" || fail "security: Cosign key is not secret"
rm -rf "$project/.devops" "$project/devops.conf"
devops init --orchestrator maven --with docker-registry,cosign > /dev/null
mkdir -p "$project/.devops/values" && printf '%s' "$WORK/cosign.key" > "$project/.devops/values/COSIGN_KEY_FILE"
devops secrets > /dev/null
! grep -q verify-image <<< "$(devops stages)" || fail "security: verify-image without a deployment"
printf 'ok  security\n'

# Secrets: Vault by its service name where the pipeline runs in Docker;
# Sealed Secrets brings Kubernetes.
for orchestrator in maven jenkins; do
  rm -rf "$project/.devops" "$project/devops.conf"
  devops init --orchestrator "$orchestrator" --with docker-registry,docker-host,vault > /dev/null
  devops secrets > /dev/null
  env_out=$(devops env --show)
  expected=http://localhost:8200; [[ $orchestrator == jenkins ]] && expected=http://vault:8200
  grep -qx "VAULT_ADDR=$expected" <<< "$env_out" || fail "vault: $orchestrator reaches Vault at the wrong address"
  grep -qx 'VAULT_APP=demo-app' <<< "$env_out" || fail "vault: application path"
  grep -qx 'VAULT_TOKEN=' <<< "$env_out" || grep -qx 'VAULT_TOKEN=\*\*\*\*\*\*\*\*' <<< "$env_out" || fail "vault: token not secret"
done
[[ $(env -i PATH="$PATH" sh "$ROOT/templates/scripts/app-secrets.sh" staging) == '{}' ]] || fail "secrets: not empty without Vault"
rm -rf "$project/.devops" "$project/devops.conf"
devops init --orchestrator maven --with docker-registry,argocd,vault,sealed-secrets > /dev/null
grep -q 'deploy/kubernetes' "$project/devops.conf" || fail "sealed-secrets: kubernetes module not added"
devops secrets > /dev/null
grep -qx 'SEALED_SECRETS=yes' <<< "$(devops env --show)" || fail "sealed-secrets: SEALED_SECRETS not set"
helm=$(sh "$ROOT/templates/scripts/tool.sh" helm 2> /dev/null || true)
if [[ -n $helm ]]; then
  chart=$("$helm" template app "$ROOT/templates/helm/app" --set secretEnv.GREETING=hi)
  grep -q 'GREETING: "hi"' <<< "$chart" || fail "chart: no Secret from secretEnv"
  grep -q 'optional: false' <<< "$chart" || fail "chart: pods do not wait for the secret"
  chart=$("$helm" template app "$ROOT/templates/helm/app" --set sealedSecretEnv.GREETING=AgB)
  grep -q 'kind: SealedSecret' <<< "$chart" || fail "chart: no SealedSecret from sealedSecretEnv"
fi
printf 'ok  secrets\n'

# Database: migrations checked in ci against the database by its service name;
# the deployment gets the connection.
for orchestrator in maven concourse; do
  rm -rf "$project/.devops" "$project/devops.conf"
  devops init --orchestrator "$orchestrator" --with docker-registry,kubernetes,postgresql > /dev/null
  devops secrets > /dev/null
  stages=$(devops stages)
  grep -q '^35 *ci *migrate .*flyway-maven-plugin:12.4.0:clean.*:migrate.*:validate' <<< "$stages" || fail "database: $orchestrator migrate stage"
  env_out=$(devops env --show)
  expected=jdbc:postgresql://localhost:5433/demo_app; [[ $orchestrator == concourse ]] && expected=jdbc:postgresql://database:5432/demo_app
  grep -qx "DATABASE_CI_URL=$expected" <<< "$env_out" || fail "database: $orchestrator reaches the ci database at the wrong address"
  grep -qx 'DATABASE_PRODUCTION_PASSWORD=\*\*\*\*\*\*\*\*' <<< "$env_out" || fail "database: password not secret"
done
secrets=$(DATABASE_ENGINE=postgresql DATABASE_NAME=demo_app DATABASE_STAGING_PASSWORD=pw \
  sh "$ROOT/templates/scripts/app-secrets.sh" staging demo-app-db)
[[ $secrets == *'"SPRING_DATASOURCE_URL": "jdbc:postgresql://demo-app-db:5432/demo_app"'*'"SPRING_DATASOURCE_PASSWORD": "pw"'* ]] \
  || fail "database: connection in the secrets: $secrets"
if [[ -n $helm ]]; then
  chart=$("$helm" template app "$ROOT/templates/helm/app" --set database.enabled=true --set database.name=demo_app)
  grep -q 'kind: StatefulSet' <<< "$chart" || fail "chart: no database"
fi
printf 'ok  database\n'

# Monitoring: Prometheus scrapes the environments the deployment has; Loki
# brings Prometheus and its Grafana data source.
rm -rf "$project/.devops" "$project/devops.conf"
devops init --orchestrator maven --with docker-registry,docker-host,loki > /dev/null
grep -q 'monitoring/prometheus' "$project/devops.conf" || fail "loki: prometheus module not added"
devops secrets > /dev/null
PATH="$WORK/fake-bin:$PATH" devops up > /dev/null
monitoring="$project/.devops/monitoring"
grep -q 'host.docker.internal:8181' "$monitoring/prometheus/prometheus.yml" || fail "prometheus: staging target missing"
grep -q 'environment: "production"' "$monitoring/prometheus/prometheus.yml" || fail "prometheus: production target missing"
grep -q 'type: loki' "$monitoring/grafana/provisioning/datasources/datasources.yml" || fail "grafana: no Loki data source"
grep -q 'demo-app-(staging|production)' "$monitoring/alloy/config.alloy" || fail "alloy: no filter on the application"
grep -q 'MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE' <<< "$(METRICS_EXPOSURE=health,prometheus sh "$ROOT/templates/scripts/app-secrets.sh" staging)" \
  || fail "monitoring: the deployment does not expose the metrics"
printf 'ok  monitoring\n'

# Load test: after staging, before production, against staging as the
# pipeline reaches it.
for orchestrator in maven jenkins; do
  rm -rf "$project/.devops" "$project/devops.conf"
  devops init --orchestrator "$orchestrator" --with docker-registry,kubernetes,k6,prometheus > /dev/null
  devops secrets > /dev/null
  stages=$(devops stages | awk 'NR > 1 { print $1 ":" $3 }' | tr '\n' ' ')
  [[ $stages == *"80:deploy-staging 85:load-test -:approval 80:deploy-production "* ]] || fail "k6: stage order $stages"
  env_out=$(devops env --show)
  expected=http://localhost:8281; [[ $orchestrator == jenkins ]] && expected=http://host.docker.internal:8281
  grep -qx "LOAD_TEST_URL=$expected" <<< "$env_out" || fail "k6: $orchestrator calls staging at the wrong address"
  expected=http://localhost:9090; [[ $orchestrator == jenkins ]] && expected=http://prometheus:9090
  grep -qx "LOAD_TEST_PROMETHEUS_URL=$expected" <<< "$env_out" || fail "k6: $orchestrator writes to the wrong Prometheus"
done
rm -rf "$project/.devops" "$project/devops.conf"
devops init --orchestrator maven --with k6 > /dev/null
! devops secrets > /dev/null 2>&1 || fail "k6: accepted without a deployment or LOAD_TEST_URL"
printf 'ok  load test\n'

# Ready-made pipelines: each one sets up and renders without questions.
[[ $(devops pipelines | grep -c '^  [a-z]') == $(find "$ROOT/pipelines" -name '*.conf' | wc -l | tr -d ' ') ]] \
  || fail "pipelines: not every ready-made pipeline is listed"
for file in "$ROOT"/pipelines/*.conf; do
  name=$(basename "$file" .conf)
  rm -rf "$project/.devops" "$project/devops.conf"
  devops init --pipeline "$name" > /dev/null
  grep -qx "PIPELINE=$name" "$project/devops.conf" || fail "pipelines: $name not recorded"
  grep -qx "ORCHESTRATOR=$(sed -n 's/^ORCHESTRATOR=//p' "$file")" "$project/devops.conf" || fail "pipelines: $name orchestrator"
  if grep -q '^TOOLS=.*cosign' "$file"; then
    mkdir -p "$project/.devops/values" && printf '%s' "$WORK/cosign.key" > "$project/.devops/values/COSIGN_KEY_FILE"
  fi
  devops secrets > /dev/null || fail "pipelines: $name secrets"
  devops render > /dev/null || fail "pipelines: $name render"
done
# Without -y only what has no default is asked: the GitHub token and the
# Nexus licence; the rest, passwords included, is taken or generated.
rm -rf "$project/.devops" "$project/devops.conf"
devops init --pipeline maven-sonarqube-nexus > /dev/null
"$ROOT/devops.sh" -p "$project" secrets <<< $'a-token\nyes' > /dev/null
[[ $(devops get GITHUB_TOKEN):$(devops get NEXUS_ACCEPT_EULA) == a-token:yes ]] || fail "pipelines: questions in the wrong order"
[[ -n $(devops get SONAR_ADMIN_PASSWORD) ]] || fail "pipelines: no generated password"
# A file of the project's own works the same way.
printf '# Own pipeline.\nORCHESTRATOR=maven\nTOOLS=sonarqube\nSONAR_HOST_PORT=9100\n' > "$WORK/own.conf"
rm -rf "$project/.devops" "$project/devops.conf"
devops init --pipeline "$WORK/own.conf" > /dev/null
grep -qx 'SONAR_HOST_PORT=9100' "$project/devops.conf" || fail "pipelines: own file not applied"
! devops init --pipeline no-such-pipeline > /dev/null 2>&1 || fail "pipelines: unknown name accepted"
printf 'ok  pipelines\n'

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
