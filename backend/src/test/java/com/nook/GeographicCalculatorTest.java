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

  @Test
  void globalCoordinatesRemainFiniteAndSymmetric() {
    double[][] cities = {{41.3874,2.1686},{51.5074,-0.1278},{40.7128,-74.0060},{35.6762,139.6503}};
    for (int index = 0; index < cities.length - 1; index++) {
      double forward = calculator.distanceKm(cities[index][0], cities[index][1],
          cities[index + 1][0], cities[index + 1][1]);
      double reverse = calculator.distanceKm(cities[index + 1][0], cities[index + 1][1],
          cities[index][0], cities[index][1]);
      assertThat(forward).isFinite().isPositive().isEqualTo(reverse);
      var midpoint = calculator.midpoint(cities[index][0], cities[index][1],
          cities[index + 1][0], cities[index + 1][1]);
      assertThat(midpoint.latitude()).isBetween(-90.0, 90.0);
      assertThat(midpoint.longitude()).isBetween(-180.0, 180.0);
    }
  }
}
