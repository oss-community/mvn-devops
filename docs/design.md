# Design

## The idea

Each tool is a self-contained module with its own scripts. `devops.sh` asks
which tool you want from each category, then runs only the scripts of those
tools, in order, until everything is running, configured and wired into a
pipeline that is ready to run.

## Categories and modules

| Category | Choice | Modules |
|---|---|---|
| Source control | required | github |
| Build | required | maven (validate, package, test, checkstyle, install) |
| Pipeline orchestrator | one | maven (on your machine), jenkins, concourse |
| Code quality | any | sonarqube |
| Artifact repositories | any | jfrog, nexus, github-packages |
| Project site | any | github-pages |

A new tool only needs a new directory under `modules/<category>/<tool>/`; the
menu finds it on its own ([module-guide.md](module-guide.md)).

## A module

```
modules/artifact/nexus/
  module.conf    name, description, modules it depends on
  compose.yml    the tool's containers
  module.sh      hooks
```

Every hook is one step of the life cycle, and every hook is optional:

| Hook | Job |
|---|---|
| `module_secrets` | ask for the values the tool needs (port, passwords, ...) |
| `module_prepare` | prepare files before the containers start |
| `module_configure` | finish setup once the tool is up: admin password, tokens, repositories |
| `module_env` | declare the variables the pipeline needs |
| `module_stages` | add Maven stages to the pipeline |
| `module_destroy` | undo what `configure` did outside Docker |
| `module_render`, `module_publish`, `module_run` | orchestrators only: build, install and run the pipeline |

Each hook runs in its own subshell, so modules cannot interfere with each
other.

## Stages come from the modules

Every module declares its stages with an order number and a phase (`ci` or
`cd`). For example sonarqube says "stage 45 in phase ci:
`sonar-maven-plugin:sonar`". The orchestrator takes the sorted list and turns
it into its own format:

- **maven** runs every stage with `mvn` on your machine.
- **jenkins** writes a Jenkinsfile and a `casc.yaml` that defines the admin
  user, the credentials and the job. No setup wizard and nothing to click.
- **concourse** writes a `pipeline.yml` with a `ci` job that runs on every
  push and a `cd` job you start by hand after `ci` passed.

So a new tool shows up in all three orchestrators at once.

## The project's pom.xml needs no profiles

`profiles.xml` only existed in Maven 2. Profiles in `settings.xml` only accept
properties, repositories and activation, not plugins or
`distributionManagement`.

So stages call every plugin by its full coordinates and configure it with
`-D`, for example
`maven-deploy-plugin:3.2.0:deploy -DaltSnapshotDeploymentRepository=nexus-snapshots::<url>`.
Credentials come from the framework's own `templates/settings.xml`, passed
with `-gs` (global settings). A project adds no profile,
`distributionManagement` or settings to its pom. A project that has its own
profiles or settings file can still use them through `MAVEN_PROFILES` and
`MAVEN_SETTINGS`.

## Project state

Everything about one project lives in two places:

- `devops.conf` in the project root, committed: the selected tools and every
  answer that is not a secret, so the whole team gets the same setup.
- `.devops/` in the project root, ignored by git: passwords and tokens, the
  generated env files and pipeline definitions, and SSH keys.

## Where the tools run

Every tool with a server (SonarQube, Nexus, Artifactory, Jenkins, Concourse)
has two modes:

- **In Docker:** devops.sh starts it, on this machine or on the machine
  `DOCKER_HOST` points to. It is reached through `DEVOPS_HOST`.
- **Existing server:** anywhere, with its own URL. `secrets` asks for
  `<TOOL>_SERVER_URL` and credentials, no container is created, and
  `configure` only checks the credentials and repositories.

Each tool is decided on its own, so any mix works.

## Life cycle

```
init  →  secrets  →  up      →  configure  →  publish          →  run
menu     questions   Docker      tokens        install pipeline    run it
```

`devops.sh setup` runs the first five steps in a row.
