# What your Maven project needs

mvn-devops runs Maven goals; the project decides what they do. Each stage
activates a profile, so the profiles below must exist in `pom.xml`.
[pine-core-java](https://github.com/oss-community/pine-core-java/blob/main/pom.xml)
has all of them and is a working example.

## Settings file

Stages run with `-s settings.xml` (question `MAVEN_SETTINGS`; leave it empty to
use your default settings). If the file is missing, `secrets` offers to copy
[templates/settings.xml](../templates/settings.xml), which declares the servers
below with credentials from environment variables.

| Server id | Used by | Credentials |
|---|---|---|
| `github` | GitHub Packages | `GITHUB_USERNAME`, `GITHUB_PACKAGE_TOKEN` |
| `nexus`, `nexus-snapshots`, `nexus-release` | Nexus | `NEXUS_ARTIFACTORY_USERNAME`, `NEXUS_ARTIFACTORY_PASSWORD` |
| `snapshots`, `releases` | JFrog | `JFROG_ARTIFACTORY_USERNAME`, `JFROG_ARTIFACTORY_ENCRYPTED_PASSWORD` |

## Profiles

| Module | Profile | Environment variables it should read |
|---|---|---|
| maven (build) | `source`, `javadoc`, `license`, `checkstyle` | none |
| sonarqube | `sonar` | `SONAR_URL`, `SONAR_TOKEN` |
| nexus | `nexus` | `NEXUS_ARTIFACTORY_HOST_URL`, `NEXUS_ARTIFACTORY_SNAPSHOT_URL`, `NEXUS_ARTIFACTORY_RELEASE_URL` |
| jfrog | `jfrog` | `JFROG_ARTIFACTORY_CONTEXT_URL`, `JFROG_ARTIFACTORY_SNAPSHOT_URL`, `JFROG_ARTIFACTORY_RELEASE_URL`, `JFROG_ARTIFACTORY_REPOSITORY_PREFIX` |
| github-packages | `github` | `GITHUB_ARTIFACTORY_URL` (owner/repo) |
| github-pages | `site`, `javadoc`, `changelog`, `test-report`, `github` | none; the site is pushed to the SCM connection |

The profile lists of the build and site stages are questions
(`MAVEN_PACKAGE_PROFILES`, `SITE_PROFILES`), so a project with other profile
names can keep them. `MAVEN_CHECKSTYLE=no` drops the checkstyle stage.

Example `sonar` profile:

```xml
<profile>
    <id>sonar</id>
    <properties>
        <sonar.host.url>${env.SONAR_URL}</sonar.host.url>
        <sonar.token>${env.SONAR_TOKEN}</sonar.token>
    </properties>
</profile>
```

## Site

`publish-site` runs `maven-scm-publish-plugin` against the project's
`<scm><connection>`, normally `scm:git:git@github.com:owner/repo.git`. Pushing
uses SSH: your own key when the `maven` orchestrator runs on your machine, and a
deploy key (generated and registered on the repository by `configure`) when
Jenkins or Concourse runs the build.

Create the `site` branch once and point GitHub Pages at it:

```bash
git checkout --orphan site
git rm -rf .
echo "site" > index.html
git add index.html && git commit -m "Initialize site" && git push origin site
git checkout main
```

Then Settings > Pages > Source: branch `site`, folder `/ (root)`.

## Tokens

The GitHub token needs `repo`, `read:org`, `write:packages`, `read:packages` and
`admin:public_key` (the last one only to register the deploy key). A separate
packages token is optional.
