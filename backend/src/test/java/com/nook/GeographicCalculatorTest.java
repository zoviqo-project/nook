package com.nook;

import static org.assertj.core.api.Assertions.assertThat;

import com.nook.service.GeographicCalculator;
import org.junit.jupiter.api.Test;

class GeographicCalculatorTest {
  private final GeographicCalculator calculator = new GeographicCalculator();

  @Test
  void midpointBetweenSantVicencAndBarcelonaIsGeographicallyBetweenBoth() {
    var point = calculator.midpoint(41.3936, 2.0093, 41.3874, 2.1686);
    assertThat(point.latitude()).isBetween(41.38, 41.41);
    assertThat(point.longitude()).isBetween(2.07, 2.10);
    assertThat(calculator.distanceKm(41.3936, 2.0093, point.latitude(), point.longitude()))
        .isBetween(6.0, 7.5);
    assertThat(calculator.distanceKm(41.3874, 2.1686, point.latitude(), point.longitude()))
        .isBetween(6.0, 7.5);
  }

  @Test
  void distanceIsZeroForSamePoint() {
    assertThat(calculator.distanceKm(41.3936, 2.0093, 41.3936, 2.0093)).isZero();
  }
}
