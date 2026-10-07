package org.example.hello;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class GreeterTest {

  @Test
  void greetsByName() {
    assertEquals("Hello, Saman!", Greeter.greet(" Saman "));
  }

  @Test
  void greetsEveryoneWithoutName() {
    assertEquals("Hello, world!", Greeter.greet(""));
    assertEquals("Hello, world!", Greeter.greet(null));
  }
}
