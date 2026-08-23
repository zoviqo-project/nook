package com.nook.service;

import static org.junit.jupiter.api.Assertions.*;
import java.time.*;
import org.junit.jupiter.api.Test;

class ShopHoursTest {
  private static final ZoneId BARCELONA = ZoneId.of("Europe/Madrid");
  private static Instant at(String value) { return ZonedDateTime.parse(value + "+02:00[Europe/Madrid]").toInstant(); }

  @Test void understandsSpanishAndRejectsAfterClosing() {
    String hours = "lunes: 08:00–20:00 · martes: 08:00–20:00";
    assertEquals(true, ShopHours.isOpenAt(hours, at("2026-08-24T18:00"), BARCELONA).orElseThrow());
    assertEquals(false, ShopHours.isOpenAt(hours, at("2026-08-24T21:00"), BARCELONA).orElseThrow());
  }

  @Test void understandsEnglishTwelveHourClockAndClosedDays() {
    String hours = "Monday: 8:00\u202fAM\u2009–\u20099:00\u202fPM · Tuesday: Closed";
    assertEquals(true, ShopHours.isOpenAt(hours, at("2026-08-24T09:00"), BARCELONA).orElseThrow());
    assertEquals(false, ShopHours.isOpenAt(hours, at("2026-08-24T21:30"), BARCELONA).orElseThrow());
    assertEquals(false, ShopHours.isOpenAt(hours, at("2026-08-25T09:00"), BARCELONA).orElseThrow());
  }

  @Test void unknownProviderTextDoesNotBlockAProposal() {
    assertTrue(ShopHours.isOpenAt("Horario pendiente", at("2026-08-24T09:00"), BARCELONA).isEmpty());
  }
}
