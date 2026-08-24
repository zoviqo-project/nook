import XCTest

@testable import Nook

final class NookTests: XCTestCase {
  func testPaymentOptionsAreComplete() { XCTAssertEqual(PaymentPreference.allCases.count, 4) }
  func testCoffeeDateStatesDecode() throws {
    let value = try JSONDecoder().decode(CoffeeDateStatus.self, from: Data("\"ACCEPTED\"".utf8))
    XCTAssertEqual(value, .accepted)
  }

  func testCoffeeDateLifecycleIncludesCounterAndExpiry() throws {
    let counter = try JSONDecoder().decode(CoffeeDateStatus.self, from: Data("\"COUNTER_PROPOSED\"".utf8))
    let expired = try JSONDecoder().decode(CoffeeDateStatus.self, from: Data("\"EXPIRED\"".utf8))
    XCTAssertEqual(counter, .counterProposed)
    XCTAssertEqual(expired, .expired)
  }

  func testCoffeeIdentityPreferencesAreEncodedForBackend() throws {
    let payload = ProfileUpdate(
      preferredVibe: "CALM", coffeesPerDay: 2, favoriteCoffeeMoment: "AFTERWORK")
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
    XCTAssertEqual(object["preferredVibe"] as? String, "CALM")
    XCTAssertEqual(object["coffeesPerDay"] as? Int, 2)
    XCTAssertEqual(object["favoriteCoffeeMoment"] as? String, "AFTERWORK")
  }

  func testGeographicMidpointBetweenSantVicencAndBarcelona() {
    let point = GeographicMath.midpoint(
      GeoPoint(latitude: 41.3936, longitude: 2.0093),
      GeoPoint(latitude: 41.3874, longitude: 2.1686))
    XCTAssertEqual(point.latitude, 41.3905, accuracy: 0.01)
    XCTAssertEqual(point.longitude, 2.0889, accuracy: 0.01)
  }

  func testKilometersAreConvertedToMeters() {
    XCTAssertEqual(GeographicMath.meters(fromKilometers: 1), 1_000)
    XCTAssertEqual(GeographicMath.meters(fromKilometers: 8), 8_000)
  }

  func testCafeSearchOriginOwnsItsCoordinates() {
    let point = GeoPoint(latitude: 41.39, longitude: 2.08)
    XCTAssertEqual(CafeSearchOrigin.midpoint(point).point, point)
    XCTAssertEqual(CafeSearchOrigin.selectedLocation(point, name: "Esplugues").logName, "SELECTED_LOCATION")
  }

  func testGeographicDistance() {
    let meters = GeographicMath.distanceMeters(
      GeoPoint(latitude: 41.3936, longitude: 2.0093),
      GeoPoint(latitude: 41.3874, longitude: 2.1686))
    XCTAssertEqual(meters, 13_300, accuracy: 600)
  }

  func testSpanishCafeHoursProduceOnlyOpenSlots() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
    let day = try XCTUnwrap(calendar.nextDate(
      after: Date(), matching: DateComponents(hour: 12, weekday: 2), matchingPolicy: .nextTime))
    let slots = try XCTUnwrap(CoffeeOpeningSchedule.slots(
      from: "lunes: 08:00–20:00 · martes: Cerrado", on: day, calendar: calendar))
    XCTAssertEqual(slots.count, 24)
    XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(slots.first)), 8)
    XCTAssertEqual(calendar.component(.minute, from: try XCTUnwrap(slots.last)), 30)
  }

  func testClosedCafeDayHasNoSlots() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
    let day = try XCTUnwrap(calendar.nextDate(
      after: Date(), matching: DateComponents(hour: 12, weekday: 3), matchingPolicy: .nextTime))
    XCTAssertEqual(CoffeeOpeningSchedule.slots(
      from: "Monday: 8:00\u{202F}AM\u{2009}–\u{2009}8:00\u{202F}PM · Tuesday: Closed", on: day, calendar: calendar), [])
  }
}
