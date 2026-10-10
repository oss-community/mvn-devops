# hello-data

A Spring Boot web API with a PostgreSQL database, for trying the database
module of mvn-devops. Flyway applies the migrations in
`src/main/resources/db/migration` when the application starts. `GET /hello`
records a visit and answers with the number of visits of that name. On
Windows, run `devops.sh` as `mvn-devops\devops.bat`.

## Run it on your machine

Step 1. Start a PostgreSQL database:

```bash
docker run -d -p 5432:5432 -e POSTGRES_USER=hello_data -e POSTGRES_PASSWORD=hello_data postgres:18
```

Step 2. Start the application:

```bash
mvn spring-boot:run
```

Step 3. In another terminal, call it:

```bash
curl localhost:8080/hello?name=you
```

## Try it with mvn-devops

Step 1. Copy the example to a GitHub repository of its own and add mvn-devops, as in steps 1 to 7 of [hello-maven](../hello-maven/README.md), with `hello-data` in place of `hello-maven`.

Step 2. Select an orchestrator, the database, a container image module and a deployment module, for example:

```bash
mvn-devops/devops.sh init --orchestrator maven --with postgresql,docker-registry,docker-host
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

- [Container images and deployment](../../docs/deployment.md): the database, container images and environments.
