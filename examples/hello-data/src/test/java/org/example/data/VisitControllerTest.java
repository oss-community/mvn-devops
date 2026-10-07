package org.example.data;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

/** The whole application, with the migrations applied to an in-memory H2. */
@SpringBootTest(properties = "spring.datasource.url=jdbc:h2:mem:test;MODE=PostgreSQL")
@AutoConfigureMockMvc
class VisitControllerTest {

  @Autowired
  private MockMvc mvc;

  @Test
  void countsVisits() throws Exception {
    mvc.perform(get("/hello").param("name", "Saman")).andExpect(jsonPath("$.visits").value(1));
    mvc.perform(get("/hello").param("name", "Saman"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.message").value("Hello, Saman!"))
        .andExpect(jsonPath("$.visits").value(2))
        .andExpect(jsonPath("$.environment").value("local"));
  }
}
