# Modules and stages

| Category | Mode | Modules |
|---|---|---|
| Source control | required | `github` |
| Build | required | `maven` (validate, package, test, checkstyle, install) |
| Pipeline orchestrator | one | `maven`, `jenkins`, `concourse` |
| Code quality | any | `sonarqube` |
| Artifact repositories | any | `jfrog`, `nexus`, `github-packages` |
| Project site | any | `github-pages` |

**Artifactory OSS** does not allow creating repositories through its API.
After `configure`, open Artifactory, choose Quick Setup > Maven and enter the
repository prefix you gave in `secrets` (`JFROG_ARTIFACTORY_REPOSITORY_PREFIX`),
so `<prefix>-libs-release-local` and `<prefix>-libs-snapshot-local` exist.
`configure` creates them itself on the Pro editions.

Default stages with every module selected (plugin coordinates shortened):

```
ORDER  PHASE STAGE            MAVEN ARGUMENTS
10     ci   validate         validate
20     ci   build            clean package -DskipTests=true
30     ci   test             test
40     ci   checkstyle       maven-checkstyle-plugin:3.6.0:check -Dcheckstyle.config.location=google_checks.xml
45     ci   sonar            sonar-maven-plugin:5.8.0.7211:sonar -Dsonar.host.url=$SONAR_URL -Dsonar.token=$SONAR_TOKEN
50     ci   install          install -DskipTests=true
60     cd   site             maven-site-plugin:3.22.0:site
62     cd   stage-site       (shell) copy the root and module sites into target/staging
65     cd   publish-site     -N maven-scm-publish-plugin:3.3.0:publish-scm -Dscmpublish.pubScmUrl=... -Dscmpublish.scmBranch=site
70     cd   deploy-jfrog     package source:jar-no-fork javadoc:jar maven-deploy-plugin:3.2.0:deploy -DaltSnapshotDeploymentRepository=jfrog-snapshots::$JFROG_ARTIFACTORY_SNAPSHOT_URL ...
71     cd   deploy-github    ... -DaltSnapshotDeploymentRepository=github::$GITHUB_PACKAGES_URL ...
72     cd   deploy-nexus     ... -DaltSnapshotDeploymentRepository=nexus-snapshots::$NEXUS_ARTIFACTORY_SNAPSHOT_URL ...
```

**The project's pom.xml needs no profiles, no distributionManagement and no
settings file.** Every plugin is called by its coordinates and configured with
`-D` properties, and credentials come from the framework's own
[settings.xml](../templates/settings.xml), passed as global settings (`-gs`).
Details and optional knobs (extra profiles, checkstyle rules, plugin versions)
are in [docs/project-requirements.md](project-requirements.md).

Adding a tool is one directory; see [docs/module-guide.md](module-guide.md).
