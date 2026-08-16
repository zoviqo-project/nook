package com.nook.service;

import org.springframework.stereotype.Component;

@Component
public class GeographicCalculator {
  public Point midpoint(double latitudeA, double longitudeA, double latitudeB, double longitudeB) {
    double lat1 = Math.toRadians(latitudeA);
    double lon1 = Math.toRadians(longitudeA);
    double lat2 = Math.toRadians(latitudeB);
    double deltaLongitude = Math.toRadians(longitudeB - longitudeA);
    double bx = Math.cos(lat2) * Math.cos(deltaLongitude);
    double by = Math.cos(lat2) * Math.sin(deltaLongitude);
    double latitude = Math.atan2(
        Math.sin(lat1) + Math.sin(lat2),
        Math.sqrt(Math.pow(Math.cos(lat1) + bx, 2) + by * by));
    double longitude = lon1 + Math.atan2(by, Math.cos(lat1) + bx);
    double normalizedLongitude = ((Math.toDegrees(longitude) + 540) % 360) - 180;
    return new Point(Math.toDegrees(latitude), normalizedLongitude);
  }

  public double distanceKm(double latitudeA, double longitudeA, double latitudeB, double longitudeB) {
    double lat = Math.toRadians(latitudeB - latitudeA);
    double lon = Math.toRadians(longitudeB - longitudeA);
    double value = Math.sin(lat / 2) * Math.sin(lat / 2)
        + Math.cos(Math.toRadians(latitudeA)) * Math.cos(Math.toRadians(latitudeB))
        * Math.sin(lon / 2) * Math.sin(lon / 2);
    return 6371 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
  }

  public record Point(double latitude, double longitude) {}
}
