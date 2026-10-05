# shellcheck shell=bash
# GitHub: repository coordinates and the credentials every other module uses.

detect_repository() {
  local url
  url=$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)
  url=${url%.git}
  case $url in
    git@github.com:*) printf '%s' "${url#git@github.com:}" ;;
    https://github.com/*) printf '%s' "${url#https://github.com/}" ;;
    ssh://git@github.com/*) printf '%s' "${url#ssh://git@github.com/}" ;;
  esac
}

detect_branch() {
  git -C "$PROJECT_DIR" symbolic-ref --short HEAD 2>/dev/null || printf 'main'
}

module_secrets() {
  ask GITHUB_REPOSITORY "GitHub repository (owner/name)" "$(detect_repository)"
  ask GIT_BRANCH "Branch the pipeline builds" "$(detect_branch)"
  ask GITHUB_USERNAME "GitHub username" "$(git config --global user.name 2>/dev/null || true)"
  ask GITHUB_EMAIL "GitHub email" "$(git config --global user.email 2>/dev/null || true)"
  log_dim "  Token scopes: repo, read:org, write:packages, read:packages, admin:public_key"
  ask_secret GITHUB_TOKEN "GitHub personal access token"
  ask_secret GITHUB_PACKAGE_TOKEN "GitHub Packages token (empty: use the token above)"
}

module_env() {
  local token package_token
  token=$(value GITHUB_TOKEN)
  package_token=$(value GITHUB_PACKAGE_TOKEN)
  package_token=${package_token:-$token}
  pipeline_var GITHUB_REPOSITORY "$(value GITHUB_REPOSITORY)"
  pipeline_var GIT_BRANCH "$(value GIT_BRANCH main)"
  pipeline_var GITHUB_USERNAME "$(value GITHUB_USERNAME)"
  pipeline_var GITHUB_EMAIL "$(value GITHUB_EMAIL)"
  pipeline_var GITHUB_TOKEN "$token"
  pipeline_secret GITHUB_PACKAGE_TOKEN "$package_token"
  # Names used by existing pom.xml/settings.xml files (pine-core-java).
  pipeline_secret GITHUB_REPOSITORY_ACCESS_TOKEN "$token"
  pipeline_var GITHUB_ARTIFACTORY_URL "$(value GITHUB_REPOSITORY)"
}

module_urls() {
  printf '  %-12s https://github.com/%s\n' GitHub "$(value GITHUB_REPOSITORY)"
}
