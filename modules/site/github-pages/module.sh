# shellcheck shell=bash
# Maven site published with maven-scm-publish-plugin to a GitHub Pages branch.
# Reports come from the project's <reporting> section when it has one,
# otherwise the site plugin's default project information pages are built.
#
# Publishing pushes over SSH.  When the pipeline runs on this machine your own
# SSH key is used.  When it runs in a container (Jenkins, Concourse) a deploy
# key is generated in .devops/keys and registered on the repository.

module_secrets() {
  ask SITE_BRANCH "Branch GitHub Pages serves" "site"
}

github_api() {
  local method=$1 path=$2; shift 2
  curl -s -X "$method" -H "Authorization: Bearer $(value GITHUB_TOKEN)" \
    -H 'Accept: application/vnd.github+json' "https://api.github.com$path" "$@"
}

module_configure() {
  local repo branch key status body
  repo=$(require_value GITHUB_REPOSITORY)
  branch=$(value SITE_BRANCH site)

  status=$(github_api GET "/repos/$repo/branches/$branch" -o /dev/null -w '%{http_code}')
  if [[ $status != 200 ]]; then
    log_warn "Branch '$branch' does not exist on $repo. Create it once (see docs/project-requirements.md#site)"
    log_warn "and select it under Settings > Pages."
  fi

  [[ ${DEVOPS_RUNS_IN:-host} == docker ]] || return 0
  key="$DEVOPS_KEYS/github_deploy"
  if [[ ! -f $key ]]; then
    ssh-keygen -q -t ed25519 -N '' -C "mvn-devops $PROJECT_NAME" -f "$key"
    log_ok "Generated deploy key $key"
  fi
  body=$(jq -nc --arg t "mvn-devops $PROJECT_NAME" --arg k "$(cat "$key.pub")" '{title: $t, key: $k, read_only: false}')
  status=$(github_api POST "/repos/$repo/keys" --data "$body" -o /dev/null -w '%{http_code}')
  case $status in
    201) log_ok "Registered the deploy key on $repo" ;;
    422) log_dim "  deploy key already registered" ;;
    *) log_warn "Could not register the deploy key (HTTP $status). Add $key.pub with write access under Settings > Deploy keys." ;;
  esac
}

# Containers get the deploy key as one base64 line; the pipeline writes it to ~/.ssh.
module_env() {
  local key="$DEVOPS_KEYS/github_deploy"
  [[ ${DEVOPS_RUNS_IN:-host} == docker && -f $key ]] || return 0
  pipeline_secret GITHUB_DEPLOY_KEY_B64 "$(base64 < "$key" | tr -d '\n')"
}

# maven-site-plugin's "stage" goal insists on <distributionManagement><site> in
# the pom, so the staging directory is assembled with a shell step instead:
# the root site plus the site of every first-level module in a sub directory.
STAGE_SITE='rm -rf target/staging && mkdir -p target/staging && cp -R target/site/. target/staging/ && for d in */target/site; do if [ -d "$d" ]; then m=$(dirname "$(dirname "$d")"); mkdir -p "target/staging/$m"; cp -R "$d/." "target/staging/$m/"; fi; done'

module_stages() {
  local scm='scm:git:git@github.com:$GITHUB_REPOSITORY.git'
  stage 60 cd site "$(mvn_site site)"
  shell_stage 62 cd stage-site "$STAGE_SITE"
  # -N: the staged site is published once, from the root.
  stage 65 cd publish-site "-N $(mvn_scm_publish) -Dscmpublish.pubScmUrl=$scm -Dscmpublish.scmBranch=$(value SITE_BRANCH site)"
}

module_urls() {
  local repo
  repo=$(value GITHUB_REPOSITORY)
  printf '  %-12s https://%s.github.io/%s\n' Site "${repo%%/*}" "${repo#*/}"
}
