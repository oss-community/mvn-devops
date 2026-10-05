# shellcheck shell=bash
# Pipeline stages.
#
# Every module may contribute stages from its module_stages hook:
#
#   stage <order> <phase> <name> "<maven arguments>"
#
#   order  number, stages run in ascending order
#   phase  ci (build, verify) or cd (publish, deploy)
#   name   short id, letters, digits and dashes
#   args   arguments passed to mvn; may use $VARS from the pipeline env
#
# The orchestrator turns the ordered list into its own format (a shell
# script, a Jenkinsfile, a Concourse pipeline).

stage() {
  local order=$1 phase=$2 name=$3 args=$4
  [[ -n ${STAGES_FILE:-} ]] || die "stage used outside module_stages"
  [[ $order =~ ^[0-9]+$ ]] || die "stage '$name': order must be a number"
  [[ $phase == ci || $phase == cd ]] || die "stage '$name': phase must be ci or cd"
  [[ $name =~ ^[a-z0-9-]+$ ]] || die "stage '$name': use lowercase letters, digits and dashes"
  # Arguments are embedded in single-quoted strings by the orchestrators.
  case $args in
    *'|'* | *"'"* | *\\* | *'${'*) die "stage '$name': arguments may not contain | ' \\ or \${" ;;
  esac
  printf '%s|%s|%s|%s\n' "$order" "$phase" "$name" "$args" >> "$STAGES_FILE"
}

# Prints "order|phase|name|args" lines for the selected modules.
pipeline_stages() {
  local tmp id
  tmp=$(mktemp)
  STAGES_FILE=$tmp
  export STAGES_FILE
  for id in $MODULES; do
    module_hook "$id" module_stages
  done
  unset STAGES_FILE
  sort -t'|' -k1,1n "$tmp"
  rm -f "$tmp"
}

# Maven flags shared by every orchestrator.  $1 is the path of the project
# root as the orchestrator sees it ("" for the current directory).
maven_flags() {
  local root=${1:-} settings flags='-B'
  settings=$(value MAVEN_SETTINGS settings.xml)
  [[ -n $root ]] && flags+=" -f $(printf '%q' "$root/pom.xml")"
  if [[ -n $settings ]]; then
    if [[ -n $root ]]; then flags+=" -s $(printf '%q' "$root/$settings")"; else flags+=" -s $settings"; fi
  fi
  printf '%s' "$flags"
}

pipeline_print() {
  local order phase name args
  printf '%-6s %-4s %-16s %s\n' ORDER PHASE STAGE 'MAVEN ARGUMENTS'
  while IFS='|' read -r order phase name args; do
    printf '%-6s %-4s %-16s %s\n' "$order" "$phase" "$name" "$args"
  done < <(pipeline_stages)
}

# Shell lines that prepare git inside a CI container: identity, plus the
# GitHub deploy key when the site module provided one.
pipeline_git_setup() {
  printf '%s' 'git config --global user.name "$GITHUB_USERNAME"; git config --global user.email "$GITHUB_EMAIL"; '
  printf '%s' 'if [ -n "$GITHUB_DEPLOY_KEY_B64" ]; then mkdir -p ~/.ssh && chmod 700 ~/.ssh; '
  printf '%s' 'echo "$GITHUB_DEPLOY_KEY_B64" | base64 -d > ~/.ssh/id_ed25519; chmod 600 ~/.ssh/id_ed25519; '
  printf '%s\n' 'ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null; fi'
}

# Pipeline variables that are secrets (masked by the orchestrators).
pipeline_secret_keys() {
  local key
  while IFS= read -r key; do
    is_secret "$key" && printf '%s\n' "$key"
  done < "$DEVOPS_ENV/pipeline.keys"
  return 0
}
