# hello-api

A small Spring Boot web API for trying the deployment modules of mvn-devops
(container image, deploy, security, secrets, monitoring). It answers
`GET /hello` with the greeting in `GREETING` (a secret in Vault, when there is
one), reports its health at `/actuator/health` and has metrics for Prometheus
at `/actuator/prometheus` when that endpoint is exposed. For the build-only
modules (code quality, artifact repositories, site) the smaller
[hello-maven](../hello-maven/README.md) is enough. On Windows, run `devops.sh`
as `mvn-devops\devops.bat`.

## Run it on your machine

Step 1. Start the application:

```bash
mvn spring-boot:run
```

Step 2. In another terminal, call it:

```bash
curl localhost:8080/hello?name=you
```

## Try it with mvn-devops

Step 1. Copy the example to a GitHub repository of its own and add mvn-devops, as in steps 1 to 7 of [hello-maven](../hello-maven/README.md), with `hello-api` in place of `hello-maven`.

Step 2. Select an orchestrator, a container image module and a deployment module, for example:

```bash
mvn-devops/devops.sh init --orchestrator maven --with docker-registry,docker-host
```

Step 3. Answer the questions and start the tools:

```bash
mvn-devops/devops.sh setup
```

Step 4. Run the pipeline:

```bash
mvn-devops/devops.sh run
```

## Next

- [Container images and deployment](../../docs/deployment.md): container images, environments, secrets and monitoring.
- [hello-data](../hello-data/README.md): the same with a PostgreSQL database.
