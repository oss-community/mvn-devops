# hello-maven

A minimal Maven project to try mvn-devops with, and the project the
end-to-end tests build. Use it for the build-only modules: code quality,
artifact repositories and the project site. On Windows, run `devops.sh` as
`mvn-devops\devops.bat`.

## Before you start

- The [prerequisites](../../docs/prerequisites.md) are installed.
- An empty GitHub repository for the example, and a GitHub token
  ([GitHub tokens and SSH keys](../../docs/github-setup.md)).

## Try it with mvn-devops

Step 1. Copy the example out of the mvn-devops repository:

```bash
cp -r examples/hello-maven ~/hello-maven
```

Step 2. Go to the copy:

```bash
cd ~/hello-maven
```

Step 3. Make it a git repository:

```bash
git init -b main
```

Step 4. Commit the files:

```bash
git add . && git commit -m "hello-maven"
```

Step 5. Add your GitHub repository as the remote:

```bash
git remote add origin git@github.com:<owner>/hello-maven.git
```

Step 6. Push it:

```bash
git push -u origin main
```

Step 7. Add mvn-devops to the project as described in [Installation](../../docs/installation.md).

Step 8. Choose the tools, answer the questions and start them:

```bash
mvn-devops/devops.sh setup
```

Step 9. Run the pipeline:

```bash
mvn-devops/devops.sh run
```

## Next

- [Getting started](../../docs/getting-started.md): guides for a ready-made pipeline or your own choice of tools.
- [hello-api](../hello-api/README.md): an example for the deployment modules.
