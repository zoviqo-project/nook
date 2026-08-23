package com.nook.service;

import java.time.*;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.*;

/** Parses the human-readable weekday descriptions returned by Google Places.
 * Unknown formats stay permissive; known closed periods are enforced. */
final class ShopHours {
  private static final Map<String, DayOfWeek> DAYS = Map.ofEntries(
      Map.entry("monday", DayOfWeek.MONDAY), Map.entry("lunes", DayOfWeek.MONDAY),
      Map.entry("tuesday", DayOfWeek.TUESDAY), Map.entry("martes", DayOfWeek.TUESDAY),
      Map.entry("wednesday", DayOfWeek.WEDNESDAY), Map.entry("miércoles", DayOfWeek.WEDNESDAY),
      Map.entry("miercoles", DayOfWeek.WEDNESDAY), Map.entry("thursday", DayOfWeek.THURSDAY),
      Map.entry("jueves", DayOfWeek.THURSDAY), Map.entry("friday", DayOfWeek.FRIDAY),
      Map.entry("viernes", DayOfWeek.FRIDAY), Map.entry("saturday", DayOfWeek.SATURDAY),
      Map.entry("sábado", DayOfWeek.SATURDAY), Map.entry("sabado", DayOfWeek.SATURDAY),
      Map.entry("sunday", DayOfWeek.SUNDAY), Map.entry("domingo", DayOfWeek.SUNDAY));
  private static final List<DateTimeFormatter> TIME_FORMATS = List.of(
      DateTimeFormatter.ofPattern("H:mm", Locale.ROOT),
      DateTimeFormatter.ofPattern("h:mm a", Locale.US));

  private ShopHours() {}

  /** Empty means the provider format was unknown. Present false means definitely closed. */
  static Optional<Boolean> isOpenAt(String descriptions, Instant instant, ZoneId zone) {
    if (descriptions == null || descriptions.isBlank()) return Optional.empty();
    ZonedDateTime local = instant.atZone(zone);
    for (String raw : descriptions.split("\\s+·\\s+")) {
      int colon = raw.indexOf(':');
      if (colon < 0) continue;
      DayOfWeek day = DAYS.get(normalize(raw.substring(0, colon)));
      if (day != local.getDayOfWeek()) continue;
      String hours = raw.substring(colon + 1).trim().replace('\u202f', ' ');
      String normalized = normalize(hours);
      if (normalized.contains("closed") || normalized.contains("cerrado")) return Optional.of(false);
      if (normalized.contains("open 24 hours") || normalized.contains("abierto 24 horas")) return Optional.of(true);
      boolean parsedAny = false;
      for (String range : hours.split(",\\s*")) {
        String[] ends = range.split("\\s*[–—-]\\s*", 2);
        if (ends.length != 2) continue;
        LocalTime start = parseTime(ends[0]);
        LocalTime end = parseTime(ends[1]);
        if (start == null || end == null) continue;
        parsedAny = true;
        LocalTime time = local.toLocalTime();
        boolean open = end.isAfter(start)
            ? !time.isBefore(start) && time.isBefore(end)
            : !time.isBefore(start) || time.isBefore(end);
        if (open) return Optional.of(true);
      }
      return parsedAny ? Optional.of(false) : Optional.empty();
    }
    return Optional.empty();
  }

  private static LocalTime parseTime(String value) {
    String clean = value.replaceAll("\\p{Zs}+", " ").trim().toUpperCase(Locale.ROOT)
        .replace("A. M.", "AM").replace("P. M.", "PM");
    for (DateTimeFormatter format : TIME_FORMATS) {
      try { return LocalTime.parse(clean, format); }
      catch (DateTimeParseException ignored) {}
    }
    return null;
  }

  private static String normalize(String value) {
    return java.text.Normalizer.normalize(value.trim().toLowerCase(Locale.ROOT), java.text.Normalizer.Form.NFC);
  }
}
