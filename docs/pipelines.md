# Ready-made pipelines

A ready-made pipeline is a tested combination of tools with its settings,
in the [pipelines](../pipelines) folder. Choose one instead of going through
the menu and the questions:

```bash
mvn-devops/devops.sh pipelines                              # what there is
mvn-devops/devops.sh setup --pipeline jenkins-complete
```

`setup` then asks only what cannot be chosen for you: your GitHub user and
token, and whether you accept the Nexus licence when Nexus is part of it.
Every password, token and key is generated for your project, so two projects
set up from the same pipeline share no secrets. The images of the tools are
downloaded when they start, as with any other setup.

| Pipeline | Orchestrator | Tools | Environments |
|---|---|---|---|
| `maven-basic` | maven-container | registry, Docker Compose over SSH | prod |
| `maven-complete` | maven-container | every tool below | dev test staging prod |
| `jenkins-complete` | Jenkins | every tool below | dev test staging prod |
| `concourse-complete` | Concourse | every tool below | dev test staging prod |

`maven-basic` builds and tests the project in a container that checks it
out of GitHub, pushes the image to a registry and runs it with Docker Compose
on a machine (a simulated one in Docker unless `DEPLOY_SERVER_URL` names
yours). It has one environment, `prod`, that needs no approval: every
pipeline that passes is deployed.

The three complete pipelines have every tool that needs no account outside
your machine: SonarQube, Nexus, a registry, Trivy, Syft and Cosign, Argo CD
on Kubernetes with Vault and Sealed Secrets, PostgreSQL, Prometheus, Grafana
and Loki, and k6. They deploy to `dev`, `test`, `staging` and `prod`; only
`prod` waits for approval and is released as a canary. They differ only in
the orchestrator. Every tool runs at once, so give Docker plenty of memory.

For any other combination, pick the tools from the menu (`init`) or write a
pipeline of your own (below). The end-to-end test runs the four pipelines
and many other combinations on GitHub's runners.

Step by step: [getting-started.md](getting-started.md#guide-1-a-ready-made-pipeline).

## What it writes

`init --pipeline` selects the pipeline's tools and writes its settings to the
project's `devops.conf`, together with `PIPELINE=<name>`. From then on the
project is like any other: commit `devops.conf`, and a teammate's `setup`
gets the same tools and settings. Change a setting in `devops.conf`, or answer
everything again with `devops.sh secrets --reconfigure`.

## A pipeline of your own

A ready-made pipeline is a `devops.conf` without the project's name: the
orchestrator, the tools as `--with` takes them, and any setting that is
neither secret nor personal. The first comment line describes it.

```properties
# Jenkins and SonarQube with three environments.
ORCHESTRATOR=jenkins
TOOLS=sonarqube,docker-registry,kubernetes
ENVIRONMENTS=dev test prod
ENV_TEST_APPROVAL=yes
ENV_PROD_APPROVAL=yes
KUBERNETES_REPLICAS=1
```

Keep the file anywhere, for example in a repository your team shares, and
pass its path:

```bash
mvn-devops/devops.sh setup --pipeline ../team/jenkins-k8s.conf
```

A file added to the `pipelines` folder of mvn-devops is listed by
`devops.sh pipelines`.
