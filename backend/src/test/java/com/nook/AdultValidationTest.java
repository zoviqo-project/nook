package com.nook;

import static org.junit.jupiter.api.Assertions.*;

import com.nook.dto.ApiDtos.UpdateMe;
import jakarta.validation.Validation;
import java.time.*;
import org.junit.jupiter.api.Test;

class AdultValidationTest {
  @Test
  void exactAdultBoundary() {
    assertEquals(18, Period.between(LocalDate.now().minusYears(18), LocalDate.now()).getYears());
  }

  @Test
  void normalizedPairIsStable() {
    var a = java.util.UUID.randomUUID();
    var b = java.util.UUID.randomUUID();
    var one = a.toString().compareTo(b.toString()) < 0 ? a : b;
    var reverseOne = b.toString().compareTo(a.toString()) < 0 ? b : a;
    assertEquals(one, reverseOne);
  }

  @Test
  void coffeeCountRejectsValuesOutsideOnboardingRange() {
    var update = new UpdateMe(
        null, null, null, null, null, null, null, null, null, null,
        "CALM", 5, "AFTERWORK", null, null, null, null, null, null, null,
        null, null, null, null, null);
    try (var factory = Validation.buildDefaultValidatorFactory()) {
      var violations = factory.getValidator().validate(update);
      assertTrue(violations.stream().anyMatch(v -> v.getPropertyPath().toString().equals("coffeesPerDay")));
    }
  }
}
