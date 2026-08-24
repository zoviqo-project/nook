package com.nook;

import static org.assertj.core.api.Assertions.assertThat;

import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.NONE)
@Testcontainers(disabledWithoutDocker=true)
class PostgresMigrationIntegrationTest {
  @Container static final PostgreSQLContainer<?> postgres =
      new PostgreSQLContainer<>("postgres:16-alpine").withDatabaseName("nook_test").withUsername("nook").withPassword("nook");

  @DynamicPropertySource static void database(DynamicPropertyRegistry registry){
    registry.add("spring.datasource.url",postgres::getJdbcUrl);
    registry.add("spring.datasource.username",postgres::getUsername);
    registry.add("spring.datasource.password",postgres::getPassword);
    registry.add("nook.google-places-api-key",()->"");
  }

  @Autowired DataSource dataSource;

  @Test void flywayCreatesCurrentProductionSchemaAndUniqueConstraints(){
    var jdbc=new JdbcTemplate(dataSource);
    Integer migrations=jdbc.queryForObject("select count(*) from flyway_schema_history where success",Integer.class);
    assertThat(migrations).isGreaterThanOrEqualTo(21);
    assertThat(jdbc.queryForObject("select count(*) from information_schema.tables where table_schema='public' and table_name in ('users','matches','coffee_date_proposals','messages','user_settings','media_objects')",Integer.class)).isEqualTo(6);
    assertThat(jdbc.queryForObject("select count(*) from pg_constraint c join pg_class t on t.oid=c.conrelid where c.contype='u' and t.relname in ('matches','coffee_likes')",Integer.class)).isEqualTo(2);
    assertThat(jdbc.queryForObject("select count(*) from information_schema.columns where table_name='user_profiles' and column_name='onboarding_step'",Integer.class)).isEqualTo(1);
  }
}
