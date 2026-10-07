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
- `doctor --fix` converts files with CRLF line endings to LF.
- `docs/troubleshooting.md`, and documentation split into topic pages.
- Container images: an `image` stage builds the application with Jib (no
  Docker or Dockerfile needed, so it works in Jenkins and Concourse too), or
  with the project's Dockerfile, and pushes it tagged with the commit and
  `latest`. The registry is the Distribution registry in Docker, an existing
  registry (Docker Hub, Harbor, Nexus, Artifactory) or the GitHub Container
  Registry. See `docs/deployment.md`.
- `examples/hello-api`, a small Spring Boot web application with a health
  endpoint, used by the deployment tests.
- Stages can call scripts from `templates/scripts/` through `$DEVOPS_SCRIPTS`.
- Deployment to a machine (`docker-host`): Docker Compose over SSH, to staging
  in the cd phase and to production after an approval. Each deployment is
  checked at the application's health endpoint and the previous image is put
  back when the check fails. Without a machine, a simulated one runs in Docker.
- A `prod` phase for stages that wait for an approval: `run --phase prod` with
  every orchestrator, an `input` step in Jenkins, a manual `prod` job in
  Concourse.
- `devops.sh rollback [staging|production] [--to TAG]`.
- Categories can be `optional`: at most one module, or none.
- Image security: Trivy scans the pushed image and fails on fixable
  vulnerabilities of `TRIVY_FAIL_ON` (default CRITICAL), Syft writes its SBOM
  (SPDX and CycloneDX), Cosign signs it with a project key, attests the SBOM
  and checks the signature before production. Signatures stay in the
  registry; the public Sigstore services are not used.
- Deployment to Kubernetes (`kubernetes`) with Helm 4: rolling updates that
  wait for the readiness probe and roll back on failure, staging and
  production namespaces, `rollback` through Helm's history. The cluster is an
  existing one (kubeconfig) or k3s in Docker. A generic chart
  (`templates/helm/app`) is used unless the project has its own.
- `templates/scripts/tool.sh` downloads pinned tools (Trivy 0.75.0, Syft
  1.54.1, Cosign 3.1.3, Helm 4.3.0) where the pipeline runs, checked against their
  release checksums and cached in `~/.cache/mvn-devops/tools`.

### Changed

- `run` with the maven orchestrator no longer runs production stages; the
  Concourse `ci` job builds the latest commit.
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
- `doctor` missed CRLF files on Windows, whose grep hides the CR.
- On Windows (Bash with igncr) `doctor` reported every file as CRLF, because igncr
  also drops the CR from `$'\r'` in the scripts.
- Generating a password could hang on macOS where SIGPIPE is ignored.

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
