# hello-data

A Spring Boot web API with a PostgreSQL database, for trying the database
module of mvn-devops. Flyway applies the migrations in
`src/main/resources/db/migration` when the application starts. `GET /hello`
records a visit and answers with the number of visits of that name.

```bash
docker run -d -p 5432:5432 -e POSTGRES_USER=hello_data -e POSTGRES_PASSWORD=hello_data postgres:18
mvn spring-boot:run
curl localhost:8080/hello?name=you
```
