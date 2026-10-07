package org.example.data;

import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Greets the caller and records the visit in the database (table visit, see
 * db/migration); the environment name shows which deployment answered.
 */
@RestController
public class VisitController {

  private final JdbcClient jdbc;
  private final String environment;

  public VisitController(JdbcClient jdbc, @Value("${app.environment:local}") String environment) {
    this.jdbc = jdbc;
    this.environment = environment;
  }

  /**
   * Records a visit of {@code name}.
   *
   * @param name who visits
   * @return the greeting, the number of visits of that name and the environment
   */
  @GetMapping("/hello")
  public Map<String, Object> hello(@RequestParam(defaultValue = "world") String name) {
    jdbc.sql("insert into visit (name) values (?)").param(name).update();
    long visits = jdbc.sql("select count(*) from visit where name = ?").param(name).query(Long.class).single();
    return Map.of("message", "Hello, " + name + "!", "visits", visits, "environment", environment);
  }
}
