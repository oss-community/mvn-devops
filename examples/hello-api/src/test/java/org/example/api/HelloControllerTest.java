package org.example.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(HelloController.class)
class HelloControllerTest {

  @Autowired
  private MockMvc mvc;

  @Test
  void greetsByName() throws Exception {
    mvc.perform(get("/hello").param("name", "Saman"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.message").value("Hello, Saman!"))
        .andExpect(jsonPath("$.environment").value("local"));
  }
}
