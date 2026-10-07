# Changelog

Every release of mvn-devops. The section of a version is also the text of its
GitHub release.

## Unreleased

### Added

- `devops.conf` in the project root holds the selected tools and every answer
  that is neither secret nor personal. Commit it: a teammate's `setup` asks only
  for their own passwords, tokens and user names. A `.devops/profile.conf` from
  1.0.0 is moved there on first use.
- `devops.sh upgrade` replaces the copy of mvn-devops inside a project with a
  release, checked against `SHA256SUMS`.
- `examples/hello-maven`, a sample project.
- An end-to-end test (`tests/e2e.sh`) that runs the real tools and the whole
  pipeline with each orchestrator on GitHub's runners.
- The smoke test also runs on macOS and on Windows (Git Bash).
- `docs/troubleshooting.md`, and documentation split into topic pages.

### Changed

- Java 21 and Maven 3.9 everywhere (Jenkins image, Concourse tasks, `doctor`).
- SonarQube Community Build 26.9 instead of the frozen `lts-community` (9.9)
  tag, PostgreSQL 18, and the latest stable Maven plugins (sonar 5.8.0.7211,
  javadoc 3.12.0, site 3.22.0, source 3.4.0, deploy 3.2.0, versions 2.22.0,
  help 3.5.2).
- The scripts keep LF line endings on Windows checkouts (`.gitattributes`),
  and `doctor` reports files that are CRLF.
- devops.sh stops with a clear message on Bash older than 4.

### Fixed

- Docker on Windows got Git Bash paths in compose files and their `.env`.

## 1.0.0

First release.

- Modules for GitHub, Maven, SonarQube, Nexus, Artifactory OSS, GitHub
  Packages and GitHub Pages; orchestrators maven (local), Jenkins
  (configuration as code) and Concourse.
- Every tool runs in Docker, on this machine or another one, or is an
  existing server with its own URL; GitHub Enterprise is supported.
- No profiles in the project's pom: plugins are called by their coordinates.
- `export-compose` writes the selected tools as one docker-compose.yml.
- `release` releases the project without maven-release-plugin.
- Packages: zip, tar.gz, deb and rpm.
