# shellcheck shell=bash
# GitHub Packages needs no container: the "github" profile of the project
# deploys to https://maven.pkg.github.com/$GITHUB_ARTIFACTORY_URL.

module_stages() {
  stage 71 cd deploy-github "deploy -DskipTests=true -P github"
}

module_urls() {
  printf '  %-12s https://github.com/%s/packages\n' Packages "$(value GITHUB_REPOSITORY)"
}
