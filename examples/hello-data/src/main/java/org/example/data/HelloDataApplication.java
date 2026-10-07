package org.example.data;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** Entry point of the sample API with a database. */
@SpringBootApplication
public class HelloDataApplication {

  public static void main(String[] args) {
    SpringApplication.run(HelloDataApplication.class, args);
  }
}
