# hello-api

A small Spring Boot web API for trying the deployment modules of mvn-devops
(container image, deploy, security, monitoring). It answers `GET /hello` and
reports its health at `/actuator/health`.

```bash
mvn spring-boot:run
curl localhost:8080/hello?name=you
```

For the build-only modules (code quality, artifact repositories, site) the
smaller [hello-maven](../hello-maven) is enough.
