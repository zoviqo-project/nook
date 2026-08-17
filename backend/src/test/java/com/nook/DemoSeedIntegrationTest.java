package com.nook;

import static org.assertj.core.api.Assertions.assertThat;

import com.nook.config.DemoDataInitializer;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest
@ActiveProfiles("demo-data")
@Testcontainers(disabledWithoutDocker = true)
class DemoSeedIntegrationTest {
  @Container
  static final PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
      .withDatabaseName("nook_demo_test").withUsername("nook").withPassword("nook");

  @DynamicPropertySource
  static void database(DynamicPropertyRegistry properties) {
    properties.add("spring.datasource.url", postgres::getJdbcUrl);
    properties.add("spring.datasource.username", postgres::getUsername);
    properties.add("spring.datasource.password", postgres::getPassword);
    properties.add("nook.jwt-secret", () -> "demo-test-secret-that-is-at-least-thirty-two-bytes");
  }

  @Autowired JdbcTemplate jdbc;
  @Autowired DemoDataInitializer initializer;

  @Test
  void demoSeedCreatesRealGlobalScenariosAndIsIdempotent() {
    Snapshot first = snapshot();
    assertThat(first.users).isEqualTo(20);
    assertThat(first.profiles).isEqualTo(20);
    assertThat(first.photos).isEqualTo(20);
    assertThat(first.cities).isEqualTo(4);
    assertThat(first.likes).isGreaterThanOrEqualTo(10);
    assertThat(first.matches).isEqualTo(1);
    assertThat(first.proposals).isEqualTo(1);
    assertThat(first.messages).isEqualTo(1);

    initializer.run();

    assertThat(snapshot()).isEqualTo(first);
  }

  private Snapshot snapshot() {
    return new Snapshot(
        count("select count(*) from users where email like '%@nook.demo'"),
        count("select count(*) from user_profiles p join users u on u.id=p.user_id where u.email like '%@nook.demo'"),
        count("select count(*) from user_photos p join users u on u.id=p.user_id where u.email like '%@nook.demo'"),
        count("select count(distinct p.city) from user_profiles p join users u on u.id=p.user_id where u.email like '%@nook.demo'"),
        count("select count(*) from coffee_likes l join users u on u.id=l.sender_id where u.email like '%@nook.demo'"),
        count("select count(*) from matches m join users u on u.id=m.user_one_id where u.email like '%@nook.demo'"),
        count("select count(*) from coffee_date_proposals d join users u on u.id=d.sender_id where u.email like '%@nook.demo'"),
        count("select count(*) from messages m join users u on u.id=m.sender_id where u.email like '%@nook.demo'"));
  }

  private int count(String sql) { return jdbc.queryForObject(sql, Integer.class); }
  private record Snapshot(int users, int profiles, int photos, int cities, int likes, int matches,
                          int proposals, int messages) {}
}
