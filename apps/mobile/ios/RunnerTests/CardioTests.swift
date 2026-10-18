import UserNotifications
import XCTest
@testable import Runner

final class CardioTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  private func at(_ seconds: TimeInterval) -> Date {
    start.addingTimeInterval(seconds)
  }

  // MARK: - Parser

  func testParserReadsEightBitHeartRate() throws {
    let measurement = try XCTUnwrap(HeartRateMeasurementParser.parse([0x00, 72]))
    XCTAssertEqual(measurement.bpm, 72)
    XCTAssertEqual(measurement.rrIntervalsMs, [])
  }

  func testParserReadsSixteenBitHeartRate() throws {
    // 0x012C = 300, little endian.
    let measurement = try XCTUnwrap(HeartRateMeasurementParser.parse([0x01, 0x2C, 0x01]))
    XCTAssertEqual(measurement.bpm, 300)
  }

  func testParserSkipsEnergyExpendedAndReadsRrIntervals() throws {
    // Flags: Energy Expended (bit 3) und RR (bit 4); bpm 8 Bit.
    let bytes: [UInt8] = [0x18, 64, 0x10, 0x00, 0x00, 0x04, 0x00, 0x02]
    let measurement = try XCTUnwrap(HeartRateMeasurementParser.parse(bytes))
    XCTAssertEqual(measurement.bpm, 64)
    // 0x0400 = 1024 -> 1000 ms, 0x0200 = 512 -> 500 ms.
    XCTAssertEqual(measurement.rrIntervalsMs, [1000, 500])
  }

  func testParserReadsSixteenBitHeartRateWithRrIntervals() throws {
    let bytes: [UInt8] = [0x11, 0x5A, 0x00, 0x00, 0x04]
    let measurement = try XCTUnwrap(HeartRateMeasurementParser.parse(bytes))
    XCTAssertEqual(measurement.bpm, 90)
    XCTAssertEqual(measurement.rrIntervalsMs, [1000])
  }

  func testParserRejectsMalformedData() {
    XCTAssertNil(HeartRateMeasurementParser.parse([]))
    XCTAssertNil(HeartRateMeasurementParser.parse([0x00]))
    XCTAssertNil(HeartRateMeasurementParser.parse([0x01, 0x50]))
    // Energy Expended angekündigt, aber abgeschnitten.
    XCTAssertNil(HeartRateMeasurementParser.parse([0x08, 70, 0x01]))
    // Halbes RR-Intervall am Ende.
    XCTAssertNil(HeartRateMeasurementParser.parse([0x10, 70, 0x00, 0x04, 0x01]))
  }

  func testRrConversionRoundsToMilliseconds() {
    XCTAssertEqual(HeartRateMeasurementParser.rrMilliseconds(fromRaw: 1024), 1000)
    XCTAssertEqual(HeartRateMeasurementParser.rrMilliseconds(fromRaw: 0), 0)
    // 819 / 1024 s = 799,8 ms -> 800.
    XCTAssertEqual(HeartRateMeasurementParser.rrMilliseconds(fromRaw: 819), 800)
  }

  func testBatteryParsingAcceptsOnlyPercentValues() {
    XCTAssertEqual(HeartRateMeasurementParser.parseBattery([87]), 87)
    XCTAssertEqual(HeartRateMeasurementParser.parseBattery([0]), 0)
    XCTAssertEqual(HeartRateMeasurementParser.parseBattery([100]), 100)
    XCTAssertNil(HeartRateMeasurementParser.parseBattery([101]))
    XCTAssertNil(HeartRateMeasurementParser.parseBattery([]))
  }

  // MARK: - Zonenalarm

  private func makeAlarm(
    low: Int? = 125,
    high: Int? = 140,
    grace: Int = 15,
    repeatEvery: Int = 60,
    warmup: Int = 0,
    alertsEnabled: Bool = true
  ) -> CardioZoneAlarm {
    CardioZoneAlarm(
      config: CardioZoneAlarmConfig(
        zoneLowBpm: low,
        zoneHighBpm: high,
        graceSeconds: grace,
        repeatSeconds: repeatEvery,
        warmupSeconds: warmup,
        startedAt: start,
        alertsEnabled: alertsEnabled
      ),
      now: start
    )
  }

  func testAlarmFiresOnlyAfterGracePeriod() {
    var alarm = makeAlarm()
    XCTAssertEqual(alarm.record(bpm: 146, at: at(0)), [])
    XCTAssertEqual(alarm.zoneState, .above)
    XCTAssertEqual(alarm.record(bpm: 146, at: at(15)), [])
    XCTAssertEqual(alarm.record(bpm: 146, at: at(16)), [.tooHigh(bpm: 146)])
  }

  func testShortSpikeDoesNotAlert() {
    var alarm = makeAlarm()
    XCTAssertEqual(alarm.record(bpm: 146, at: at(0)), [])
    XCTAssertEqual(alarm.record(bpm: 146, at: at(10)), [])
    XCTAssertEqual(alarm.record(bpm: 135, at: at(11)), [])
    XCTAssertEqual(alarm.zoneState, .inZone)
    // Ein neuer Ausreißer beginnt die Karenzzeit von vorn.
    XCTAssertEqual(alarm.record(bpm: 146, at: at(20)), [])
    XCTAssertEqual(alarm.record(bpm: 146, at: at(30)), [])
  }

  func testAlarmRepeatsAtMostEveryRepeatInterval() {
    var alarm = makeAlarm()
    _ = alarm.record(bpm: 120, at: at(0))
    XCTAssertEqual(alarm.record(bpm: 120, at: at(16)), [.tooLow(bpm: 120)])
    XCTAssertEqual(alarm.record(bpm: 120, at: at(40)), [])
    XCTAssertEqual(alarm.record(bpm: 118, at: at(75)), [])
    XCTAssertEqual(alarm.record(bpm: 118, at: at(76)), [.tooLow(bpm: 118)])
  }

  func testBackInZoneIsReportedOnceAfterAnAlert() {
    var alarm = makeAlarm()
    _ = alarm.record(bpm: 120, at: at(0))
    XCTAssertEqual(alarm.record(bpm: 120, at: at(20)), [.tooLow(bpm: 120)])
    XCTAssertEqual(alarm.record(bpm: 130, at: at(25)), [.backInZone])
    XCTAssertEqual(alarm.record(bpm: 131, at: at(26)), [])
  }

  func testNoAlertWhileWarmingUpAndGraceStartsAfterWarmup() {
    var alarm = makeAlarm(warmup: 180)
    XCTAssertEqual(alarm.record(bpm: 100, at: at(60)), [])
    XCTAssertEqual(alarm.record(bpm: 100, at: at(170)), [])
    XCTAssertEqual(alarm.zoneState, .below)
    // Karenz zählt erst ab Ende der Aufwärmzeit.
    XCTAssertEqual(alarm.record(bpm: 100, at: at(185)), [])
    XCTAssertEqual(alarm.record(bpm: 100, at: at(196)), [.tooLow(bpm: 100)])
  }

  func testSignalLostFiresOnceAndIsRearmedByNextReading() {
    var alarm = makeAlarm()
    _ = alarm.record(bpm: 130, at: at(0))
    XCTAssertEqual(alarm.tick(now: at(25)), [])
    XCTAssertEqual(alarm.tick(now: at(31)), [.signalLost])
    XCTAssertEqual(alarm.zoneState, .noSignal)
    XCTAssertEqual(alarm.tick(now: at(60)), [])
    XCTAssertEqual(alarm.record(bpm: 130, at: at(70)), [])
    XCTAssertEqual(alarm.zoneState, .inZone)
    XCTAssertEqual(alarm.tick(now: at(101)), [.signalLost])
  }

  func testSignalLostWithoutAnyReadingCountsFromMonitoringStart() {
    var alarm = makeAlarm()
    XCTAssertEqual(alarm.tick(now: at(10)), [])
    XCTAssertEqual(alarm.tick(now: at(31)), [.signalLost])
  }

  func testNoZoneMeansNoZoneAlerts() {
    var alarm = makeAlarm(low: nil, high: nil)
    XCTAssertEqual(alarm.record(bpm: 200, at: at(0)), [])
    XCTAssertEqual(alarm.record(bpm: 200, at: at(60)), [])
    XCTAssertEqual(alarm.zoneState, .none)
    XCTAssertEqual(alarm.tick(now: at(95)), [.signalLost])
  }

  func testUpdatingTheZoneKeepsTheSessionAndReevaluates() {
    var alarm = makeAlarm()
    _ = alarm.record(bpm: 146, at: at(0))
    XCTAssertEqual(alarm.record(bpm: 146, at: at(20)), [.tooHigh(bpm: 146)])

    var config = alarm.config
    config.zoneLowBpm = 130
    config.zoneHighBpm = 150
    XCTAssertEqual(alarm.update(config: config, now: at(21)), [.backInZone])
    XCTAssertEqual(alarm.zoneState, .inZone)
  }

  func testDisabledAlertsStillTrackZoneState() {
    var alarm = makeAlarm(alertsEnabled: false)
    _ = alarm.record(bpm: 146, at: at(0))
    XCTAssertEqual(alarm.record(bpm: 146, at: at(60)), [])
    XCTAssertEqual(alarm.zoneState, .above)
    XCTAssertEqual(alarm.tick(now: at(100)), [])
  }

  // MARK: - Benachrichtigungen

  func testCardioNotificationsArePresentedWhileTheAppIsOpen() {
    XCTAssertEqual(
      TimerNotificationDelegate.presentationOptions(forIdentifier: NativeCardioAlerts.identifier(forKind: "zone")),
      [.banner, .sound, .list]
    )
    XCTAssertEqual(
      TimerNotificationDelegate.presentationOptions(forIdentifier: "com.gainer.mobile.cardio.signal"),
      [.banner, .sound, .list]
    )
    XCTAssertNil(TimerNotificationDelegate.presentationOptions(forIdentifier: "com.gainer.mobile.cardiology"))
  }

  func testCardioAlertTexts() {
    let high = CardioAlertMessage.make(for: .tooHigh(bpm: 146), zoneLowBpm: 125, zoneHighBpm: 140)
    XCTAssertEqual(high.title, "Puls zu hoch")
    XCTAssertEqual(high.body, "146 bpm – Ziel 125–140")
    XCTAssertTrue(high.playsSound)

    let low = CardioAlertMessage.make(for: .tooLow(bpm: 118), zoneLowBpm: 125, zoneHighBpm: 140)
    XCTAssertEqual(low.title, "Puls zu niedrig")

    let back = CardioAlertMessage.make(for: .backInZone, zoneLowBpm: 125, zoneHighBpm: 140)
    XCTAssertEqual(back.title, "Wieder im Zielbereich")
    XCTAssertFalse(back.playsSound)
    XCTAssertEqual(back.kind, high.kind)

    let lost = CardioAlertMessage.make(for: .signalLost, zoneLowBpm: nil, zoneHighBpm: nil)
    XCTAssertEqual(lost.title, "Kein Pulssignal")
    XCTAssertEqual(lost.body, "Prüfe den Sitz des Gurts.")
  }

  // MARK: - Live Activity

  func testLiveActivityThrottlePushesZoneChangesImmediatelyAndBpmAtMostEveryFiveSeconds() {
    var throttle = CardioLiveActivityThrottle()
    XCTAssertTrue(throttle.shouldPush(zoneState: "inZone", bpm: 130, now: at(0)))
    XCTAssertFalse(throttle.shouldPush(zoneState: "inZone", bpm: 131, now: at(2)))
    XCTAssertTrue(throttle.shouldPush(zoneState: "above", bpm: 141, now: at(3)))
    XCTAssertFalse(throttle.shouldPush(zoneState: "above", bpm: 141, now: at(20)))
    XCTAssertTrue(throttle.shouldPush(zoneState: "above", bpm: 143, now: at(8)))
  }

  // MARK: - Apple Health

  func testCardioSyncIdentifierIsStableAndNeedsUuids() throws {
    let account = "11111111-1111-4111-8111-111111111111"
    let session = "22222222-2222-4222-8222-222222222222"
    let identifier = try XCTUnwrap(NativeHealthKit.stableCardioSyncIdentifier(accountId: account, sessionId: session))
    XCTAssertEqual(
      identifier,
      NativeHealthKit.stableCardioSyncIdentifier(accountId: account.uppercased(), sessionId: session.uppercased())
    )
    XCTAssertTrue(identifier.hasPrefix("gainer.cardio."))
    XCTAssertNotEqual(
      identifier,
      NativeHealthKit.stableWorkoutSyncIdentifier(accountId: account, workoutId: session)
    )
    XCTAssertNil(NativeHealthKit.stableCardioSyncIdentifier(accountId: "nope", sessionId: session))
  }

  func testHeartRateWindowsSkipNoSignalAndClampToTheEnd() {
    let windows = NativeHealthKit.heartRateWindows(
      startedAt: start,
      completedAt: at(12),
      intervalSeconds: 5,
      heartRateBpm: [120, 0, 130, 140]
    )
    XCTAssertEqual(
      windows,
      [
        NativeHeartRateWindow(start: at(0), end: at(5), bpm: 120),
        NativeHeartRateWindow(start: at(10), end: at(12), bpm: 130),
      ]
    )
  }

  // MARK: - Eingabeprüfung

  private func config(low: Int64?, high: Int64?, grace: Int64 = 15, repeatEvery: Int64 = 60, warmup: Int64 = 180)
    -> PlatformCardioMonitoringConfig
  {
    PlatformCardioMonitoringConfig(
      sessionId: "22222222-2222-4222-8222-222222222222",
      title: "Rad-Ergometer",
      startedAtUtcEpochMilliseconds: 1_800_000_000_000,
      graceSeconds: grace,
      repeatSeconds: repeatEvery,
      warmupSeconds: warmup,
      soundId: "digital_alarm",
      alertsEnabled: true,
      liveActivityEnabled: false,
      zoneLowBpm: low,
      zoneHighBpm: high
    )
  }

  func testCardioConfigValidation() {
    XCTAssertNoThrow(try GainerMobilePlatform.validate(cardioConfig: config(low: 125, high: 140)))
    XCTAssertNoThrow(try GainerMobilePlatform.validate(cardioConfig: config(low: nil, high: nil)))
    XCTAssertThrowsError(try GainerMobilePlatform.validate(cardioConfig: config(low: 140, high: 125)))
    XCTAssertThrowsError(try GainerMobilePlatform.validate(cardioConfig: config(low: 30, high: 140)))
    XCTAssertThrowsError(try GainerMobilePlatform.validate(cardioConfig: config(low: 120, high: 231)))
    XCTAssertThrowsError(try GainerMobilePlatform.validate(cardioConfig: config(low: 120, high: nil)))
    XCTAssertThrowsError(try GainerMobilePlatform.validate(cardioConfig: config(low: 120, high: 140, warmup: 601)))
    XCTAssertThrowsError(try GainerMobilePlatform.validate(cardioConfig: config(low: 120, high: 140, repeatEvery: 0)))
  }
}
