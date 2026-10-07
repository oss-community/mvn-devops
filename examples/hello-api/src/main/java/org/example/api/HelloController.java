package org.example.api;

import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Greets the caller; the environment name shows which deployment answered.
 * The greeting is a setting of the environment (GREETING), kept as a secret.
 */
@RestController
public class HelloController {

  private final String environment;
  private final String greeting;

  public HelloController(@Value("${app.environment:local}") String environment,
      @Value("${app.greeting:Hello}") String greeting) {
    this.environment = environment;
    this.greeting = greeting;
  }

  /**
   * Returns a greeting.
   *
   * @param name who to greet
   * @return the greeting and the environment
   */
  @GetMapping("/hello")
  public Map<String, String> hello(@RequestParam(defaultValue = "world") String name) {
    return Map.of("message", greeting + ", " + name + "!", "environment", environment);
  }
}
