# mvn-devops

A modular DevOps framework for Maven projects, written in plain Bash.

You pick the tools from a menu, mvn-devops starts them in Docker, configures
them (admin passwords, tokens, repositories) and turns the stages they
contribute into a pipeline for the orchestrator you chose: plain `mvn` on your
machine, Jenkins or Concourse.

```
$ ./devops.sh -p ../pine-core-java init

Pipeline orchestrator (choose one)
  1) concourse        Concourse CI in Docker: a ci job on every push, a manual cd job
  2) jenkins          Jenkins in Docker, configured as code (no setup wizard)
  3) maven            Run the stages with mvn directly on this machine
  > [1]: 2

Code quality (choose any, comma separated, 0 for none)
  1) sonarqube        Static code analysis (SonarQube Community + PostgreSQL)
  > [0]: 1

Artifact repositories (choose any, comma separated, 0 for none)
  1) github-packages  Deploy to the Maven registry of the GitHub repository
  2) jfrog            JFrog Artifactory OSS + PostgreSQL
  3) nexus            Sonatype Nexus 3 for Maven releases and snapshots
  > [0]: 1,3
...
```

It grew out of the shell scripts in
[pine-core-java](https://github.com/oss-community/pine-core-java), where every
orchestrator had its own copy of every tool. Here each tool is a module with its
own script, and one entry point asks which modules you want.

## Prerequisites

- Bash 4+ (Linux, macOS, or Git Bash on Windows; `devops.bat` finds it for you)
- Docker with the compose plugin
- `curl`, `jq`, `git`, `ssh-keygen`
- Java and Maven when the `maven` orchestrator runs the pipeline locally

`./devops.sh doctor` checks all of them.

## Quick start

```bash
git clone https://github.com/oss-community/mvn-devops.git
cd my-maven-project
../mvn-devops/devops.sh setup      # menu, questions, containers, tokens, pipeline
../mvn-devops/devops.sh run        # run the pipeline
../mvn-devops/devops.sh urls       # web consoles and how to log in
```

`setup` is the five steps below in order; each can also be run on its own.

| Step | Command | What happens |
|---|---|---|
| 1 | `init` | Menu per category. Saves the choice in `.devops/profile.conf`. |
| 2 | `secrets` | Each selected module asks for the values it needs. Passwords default to random ones. |
| 3 | `up` | Modules prepare (render config, keys), then `docker compose up` with every selected module's compose fragment. |
| 4 | `configure` | Modules finish their tool: change default admin passwords, create tokens and repositories. |
| 5 | `publish` | The orchestrator renders the pipeline and installs it (Jenkins job, Concourse pipeline, local script). |

Without questions, for scripts and CI:

```bash
./devops.sh -y -p ../pine-core-java init --orchestrator jenkins --with sonarqube,nexus,github-pages
./devops.sh -y -p ../pine-core-java setup
```

## Commands

| Command | |
|---|---|
| `init [--orchestrator X --with a,b]` | choose modules |
| `setup` | init (if needed) + secrets + up + configure + publish |
| `secrets [--reconfigure]` | ask for values; `--reconfigure` asks again |
| `up`, `configure`, `publish` | single setup steps |
| `stages` | the ordered stages contributed by the selected modules |
| `render` | write pipeline files into `.devops/generated` |
| `run` | run the pipeline. maven: `--dry-run`, `--from <stage>`, `--only <stage>`, `--phase ci\|cd`. concourse: `--phase ci\|cd` |
| `status`, `urls`, `logs [service]`, `compose ...` | operations |
| `down` | stop containers, keep data |
| `destroy` | remove containers and volumes, optionally the stored values |
| `env [--show\|--windows]` | regenerate env files; `--show` masks secrets; `--windows` writes a `setx` script for IDEs on Windows |
| `get <KEY>` | print one stored value, e.g. `get SONAR_ADMIN_PASSWORD` |
| `modules`, `doctor` | list modules, check prerequisites |

## Modules

| Category | Mode | Modules |
|---|---|---|
| Source control | required | `github` |
| Build | required | `maven` (validate, package, test, checkstyle, install) |
| Pipeline orchestrator | one | `maven`, `jenkins`, `concourse` |
| Code quality | any | `sonarqube` |
| Artifact repositories | any | `jfrog`, `nexus`, `github-packages` |
| Project site | any | `github-pages` |

Default stages with every module selected (plugin coordinates shortened):

```
ORDER  PHASE STAGE            MAVEN ARGUMENTS
10     ci   validate         validate
20     ci   build            clean package -DskipTests=true
30     ci   test             test
40     ci   checkstyle       maven-checkstyle-plugin:3.6.0:check -Dcheckstyle.config.location=google_checks.xml
45     ci   sonar            sonar-maven-plugin:4.0.0.4121:sonar -Dsonar.host.url=$SONAR_URL -Dsonar.token=$SONAR_TOKEN
50     ci   install          install -DskipTests=true
60     cd   site             maven-site-plugin:3.21.0:site
62     cd   stage-site       (shell) copy the root and module sites into target/staging
65     cd   publish-site     -N maven-scm-publish-plugin:3.3.0:publish-scm -Dscmpublish.pubScmUrl=... -Dscmpublish.scmBranch=site
70     cd   deploy-jfrog     package source:jar-no-fork javadoc:jar maven-deploy-plugin:3.1.3:deploy -DaltSnapshotDeploymentRepository=jfrog-snapshots::$JFROG_ARTIFACTORY_SNAPSHOT_URL ...
71     cd   deploy-github    ... -DaltSnapshotDeploymentRepository=github::$GITHUB_PACKAGES_URL ...
72     cd   deploy-nexus     ... -DaltSnapshotDeploymentRepository=nexus-snapshots::$NEXUS_ARTIFACTORY_SNAPSHOT_URL ...
```

**The project's pom.xml needs no profiles, no distributionManagement and no
settings file.** Every plugin is called by its coordinates and configured with
`-D` properties, and credentials come from the framework's own
[settings.xml](templates/settings.xml), passed as global settings (`-gs`).
Details and optional knobs (extra profiles, checkstyle rules, plugin versions)
are in [docs/project-requirements.md](docs/project-requirements.md).

Adding a tool is one directory; see [docs/module-guide.md](docs/module-guide.md).

## Project site on GitHub Pages

The `github-pages` module builds the Maven site and pushes it to a `site`
branch, which GitHub Pages serves. Two things have to be done once by hand.

**1. Create the `site` branch** in your project repository. It is an orphan
branch that only holds the published site:

```bash
git checkout --orphan site
git rm -rf --cached . > /dev/null
echo "site" > index.html
git add index.html
git commit -m "Initialize site"
git push origin site
git checkout -f main
```

`git checkout -f main` restores your working tree; untracked files such as
`.devops/` are left alone. Use another branch name by answering the
`SITE_BRANCH` question in `secrets`.

**2. Point GitHub Pages at it.** In the GitHub repository go to
Settings > Pages, and under Build and deployment set:

- Source: Deploy from a branch
- Branch: `site`, folder `/ (root)`

The site is then served at `https://<owner>.github.io/<repo>/`, for example
[oss-community.github.io/pine-core-java](https://oss-community.github.io/pine-core-java).

**Publishing.** The site stages run in the `cd` phase, after the ci stages:

```bash
./devops.sh run --phase cd            # site, stage-site, publish-site and the deploys
./devops.sh run --only publish-site   # push an already built and staged site again
```

**Maven by hand.** The same steps as plain Maven commands, run in the project
root. No profiles or settings are needed:

```bash
# build the site, including module sites
mvn -B org.apache.maven.plugins:maven-site-plugin:3.21.0:site

# preview it at http://localhost:8000
mvn org.apache.maven.plugins:maven-site-plugin:3.21.0:run -Dport=8000

# publish target/staging to the site branch (after ./devops.sh run --only stage-site)
mvn -B -N org.apache.maven.plugins:maven-scm-publish-plugin:3.3.0:publish-scm \
  -Dscmpublish.pubScmUrl=scm:git:git@github.com:<owner>/<repo>.git \
  -Dscmpublish.scmBranch=site
```

`./devops.sh stages` prints the exact command of every stage for your
selection. Pushing uses SSH: your own key with the `maven` orchestrator, and a
deploy key that `configure` registers on the repository with Jenkins or
Concourse.

## How it fits together

```
devops.sh ── lib/  (menu, value store, env files, stages, compose)
   │
   └── modules/<category>/<tool>/
         module.conf    title, description, requirements
         module.sh      hooks: module_secrets, module_prepare, module_configure,
                        module_env, module_stages, module_urls
                        (+ module_render, module_publish, module_run for orchestrators)
         compose.yml    containers of the tool (optional)
```

All state for a project is kept in `<project>/.devops/` (it git-ignores itself):

```
.devops/
  profile.conf          selected modules
  values/<KEY>          one file per value, chmod 600
  env/pipeline.env      variables handed to the pipeline (compose env_file format)
  env/pipeline.sh       the same as bash exports
  env/compose.env       everything, for ${VAR} substitution in compose files
  generated/            Jenkinsfile, jenkins/casc.yaml, concourse/*.yml, pipeline.sh
  keys/                 generated SSH deploy key
```

Nothing is written to `~/.bashrc` or to system environment variables, and
secrets are never printed: `env --show` masks them and the orchestrators bind
them as masked credentials.

URLs handed to the pipeline depend on where it runs: with the `maven`
orchestrator they point to `localhost:<port>`, with Jenkins or Concourse to the
compose service name (`http://sonarqube:9000`), because the build runs inside
the same Docker network.

## Orchestrators

**maven** runs each stage with `mvn` on your machine, with the pipeline
variables exported only for that process. `render` also writes
`.devops/generated/pipeline.sh` for IDE run configurations.

**jenkins** builds an image from `jenkins/jenkins:lts-jdk17` with Maven and the
needed plugins, skips the setup wizard and configures everything with
Configuration as Code: the admin user, one secret-text credential per secret and
a pipeline job generated from the stages. `run` triggers the job and streams its
console.

**concourse** runs `concourse quickstart` (web and worker in one container).
The pipeline has a `ci` job, triggered by every push, and a `cd` job that runs
all stages and is started by hand after `ci` passed. Tasks run in
`maven:3.9-eclipse-temurin-17`. `fly` is downloaded from the server.

## Testing

```bash
tests/smoke.sh            # every orchestrator: init, secrets, stages, render, compose config
shellcheck devops.sh lib/*.sh modules/*/*/module.sh tests/*.sh
```

## License

Apache License 2.0
