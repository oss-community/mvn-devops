# shellcheck shell=bash
# Core Maven stages.  Profiles (source, javadoc, license, checkstyle) must exist
# in the project's pom.xml; see docs/project-requirements.md.

module_secrets() {
  ask MAVEN_SETTINGS "Maven settings file, relative to the project (empty: none)" "settings.xml"
  ask MAVEN_PACKAGE_PROFILES "Profiles used when packaging (empty: none)" "source,javadoc,license"
  ask MAVEN_CHECKSTYLE "Run checkstyle (-P checkstyle)? yes/no" "yes"
  if [[ -n $(value MAVEN_SETTINGS) && ! -f "$PROJECT_DIR/$(value MAVEN_SETTINGS)" ]]; then
    log_warn "$PROJECT_DIR/$(value MAVEN_SETTINGS) does not exist."
    if confirm "  Copy the template settings.xml from mvn-devops?" y; then
      cp "$DEVOPS_HOME/templates/settings.xml" "$PROJECT_DIR/$(value MAVEN_SETTINGS)"
      log_ok "Copied templates/settings.xml"
    fi
  fi
}

module_stages() {
  local profiles
  profiles=$(value MAVEN_PACKAGE_PROFILES)
  stage 10 ci validate "validate"
  stage 20 ci build "clean package -DskipTests=true${profiles:+ -P $profiles}"
  stage 30 ci test "test"
  if [[ $(value MAVEN_CHECKSTYLE yes) =~ ^[Yy] ]]; then
    stage 40 ci checkstyle "checkstyle:check -P checkstyle"
  fi
  stage 50 ci install "install -DskipTests=true"
}
