package org.example.api;

import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Greets the caller; the environment name shows which deployment answered. */
@RestController
public class HelloController {

  private final String environment;

  public HelloController(@Value("${app.environment:local}") String environment) {
    this.environment = environment;
  }

  /**
   * Returns a greeting.
   *
   * @param name who to greet
   * @return the greeting and the environment
   */
  @GetMapping("/hello")
  public Map<String, String> hello(@RequestParam(defaultValue = "world") String name) {
    return Map.of("message", "Hello, " + name + "!", "environment", environment);
  }
}
