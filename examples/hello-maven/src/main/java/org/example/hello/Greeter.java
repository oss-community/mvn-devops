package org.example.hello;

/**
 * Builds greetings.
 */
public final class Greeter {

  private Greeter() {
  }

  /**
   * Returns a greeting for the given name.
   *
   * @param name who to greet; blank means everyone
   * @return the greeting
   */
  public static String greet(String name) {
    if (name == null || name.isBlank()) {
      return "Hello, world!";
    }
    return "Hello, " + name.strip() + "!";
  }

  /**
   * Prints a greeting for the first argument.
   *
   * @param args optional name
   */
  public static void main(String[] args) {
    System.out.println(greet(args.length > 0 ? args[0] : null));
  }
}
