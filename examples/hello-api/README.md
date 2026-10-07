# hello-api

A small Spring Boot web API for trying the deployment modules of mvn-devops
(container image, deploy, security, secrets, monitoring). It answers
`GET /hello` with the greeting in `GREETING` (a secret in Vault, when there is
one), reports its health at `/actuator/health` and has metrics for Prometheus
at `/actuator/prometheus` when that endpoint is exposed.

```bash
mvn spring-boot:run
curl localhost:8080/hello?name=you
```

For the build-only modules (code quality, artifact repositories, site) the
smaller [hello-maven](../hello-maven) is enough.
