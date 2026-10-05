# shellcheck shell=bash
# GitHub Packages needs no container: artifacts go to
# https://maven.pkg.github.com/<owner>/<repo>.

module_env() {
  pipeline_var GITHUB_PACKAGES_URL "https://maven.pkg.github.com/$(value GITHUB_REPOSITORY)"
}

module_stages() {
  stage 71 cd deploy-github "$(mvn_deploy_args github '$GITHUB_PACKAGES_URL' github '$GITHUB_PACKAGES_URL')"
}

module_urls() {
  printf '  %-12s https://github.com/%s/packages\n' Packages "$(value GITHUB_REPOSITORY)"
}
