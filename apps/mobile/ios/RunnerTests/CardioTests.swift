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

  // MARK: - Phasen

  private func makePhaseAlarm(alertsEnabled: Bool = true) -> CardioZoneAlarm {
    // Aufwärmen 0–600 s Ziel 110–130, Belastung 600–840 s Ziel 152–171, Ausfahren 840–900 s ohne Zone.
    CardioZoneAlarm(
      config: CardioZoneAlarmConfig(
        zoneLowBpm: nil,
        zoneHighBpm: nil,
        graceSeconds: 15,
        repeatSeconds: 60,
        warmupSeconds: 0,
        startedAt: start,
        alertsEnabled: alertsEnabled,
        phases: [
          CardioPhase(startOffsetSeconds: 0, durationSeconds: 600, name: "Aufwärmen", zoneLowBpm: 110, zoneHighBpm: 130),
          CardioPhase(startOffsetSeconds: 600, durationSeconds: 240, name: "Belastung", zoneLowBpm: 152, zoneHighBpm: 171),
          CardioPhase(startOffsetSeconds: 840, durationSeconds: 60, name: "Ausfahren", zoneLowBpm: nil, zoneHighBpm: nil),
        ]
      ),
      now: start
    )
  }

  func testPhaseEventsAndZoneSwitching() {
    var alarm = makePhaseAlarm(alertsEnabled: false)
    XCTAssertEqual(
      alarm.tick(now: at(0)),
      [.phaseStarted(index: 0, count: 3, name: "Aufwärmen", durationSeconds: 600, zoneLowBpm: 110, zoneHighBpm: 130)]
    )
    XCTAssertEqual(alarm.activeZone, 110...130)
    XCTAssertEqual(alarm.tick(now: at(300)), [])

    XCTAssertEqual(
      alarm.tick(now: at(600)),
      [.phaseStarted(index: 1, count: 3, name: "Belastung", durationSeconds: 240, zoneLowBpm: 152, zoneHighBpm: 171)]
    )
    XCTAssertEqual(alarm.activeZone, 152...171)
    XCTAssertEqual(alarm.currentPhaseIndex, 1)

    // Phase ohne Zone: keine Zone, aber die Phase wird gemeldet.
    XCTAssertEqual(
      alarm.tick(now: at(840)),
      [.phaseStarted(index: 2, count: 3, name: "Ausfahren", durationSeconds: 60, zoneLowBpm: nil, zoneHighBpm: nil)]
    )
    XCTAssertNil(alarm.activeZone)

    XCTAssertEqual(alarm.tick(now: at(900)), [.templateFinished])
    XCTAssertNil(alarm.currentPhaseIndex)
    XCTAssertEqual(alarm.tick(now: at(960)), [])
  }

  func testZoneStateFollowsThePhaseZone() {
    var alarm = makePhaseAlarm()
    _ = alarm.record(bpm: 120, at: at(100))
    XCTAssertEqual(alarm.zoneState, .inZone)
    _ = alarm.record(bpm: 120, at: at(601))
    XCTAssertEqual(alarm.zoneState, .below)
  }

  func testGraceRestartsAtPhaseStart() {
    var alarm = makePhaseAlarm()
    // Die Belastung beginnt mit Puls 140 bei Ziel 152–171.
    _ = alarm.record(bpm: 140, at: at(590))
    let started = alarm.record(bpm: 140, at: at(600))
    XCTAssertEqual(started.count, 1)
    XCTAssertEqual(alarm.zoneState, .below)
    // Innerhalb der Karenz von 15 s steigt der Puls in die Zone: kein Alarm.
    XCTAssertEqual(alarm.record(bpm: 145, at: at(610)), [])
    XCTAssertEqual(alarm.record(bpm: 155, at: at(614)), [])
    XCTAssertEqual(alarm.zoneState, .inZone)
    XCTAssertEqual(alarm.tick(now: at(640)), [])
  }

  func testPhaseChangeResetsAnOutsideStreak() {
    var alarm = makePhaseAlarm()
    // 135 bpm ist im Aufwärmen über dem Ziel; die Karenz läuft fast ab.
    _ = alarm.record(bpm: 135, at: at(580))
    XCTAssertEqual(alarm.record(bpm: 135, at: at(594)), [])
    // Mit der neuen Phase beginnt die Karenz neu, kein Alarm vor 615 s.
    _ = alarm.record(bpm: 135, at: at(600))
    XCTAssertEqual(alarm.record(bpm: 135, at: at(614)), [])
    XCTAssertEqual(alarm.record(bpm: 135, at: at(616)), [.tooLow(bpm: 135)])
  }

  func testNoPhaseEventsWithoutPhasesAndNoTemplateEndAfterLateStart() {
    var plain = makeAlarm()
    XCTAssertEqual(plain.tick(now: at(10)), [])
    XCTAssertNil(plain.currentPhaseIndex)

    // Nach einem Neustart hinter dem Ende wird nichts mehr angekündigt.
    var late = makePhaseAlarm(alertsEnabled: false)
    XCTAssertEqual(late.tick(now: at(5000)), [])
  }

  func testPhaseEventsIgnoreDisabledAlerts() {
    var alarm = makePhaseAlarm(alertsEnabled: false)
    XCTAssertEqual(alarm.tick(now: at(0)).count, 1)
  }

  // MARK: - Sprache

  func testVoiceTextsForZoneEvents() {
    XCTAssertEqual(CardioVoiceText.text(for: .tooHigh(bpm: 146)), "Puls 146, über dem Ziel. Etwas langsamer.")
    XCTAssertEqual(CardioVoiceText.text(for: .tooLow(bpm: 118)), "Puls 118, unter dem Ziel. Etwas schneller.")
    XCTAssertEqual(CardioVoiceText.text(for: .backInZone), "Wieder im Zielbereich.")
    XCTAssertEqual(CardioVoiceText.text(for: .signalLost), "Kein Pulssignal.")
    XCTAssertEqual(CardioVoiceText.text(for: .templateFinished), "Vorlage beendet.")
  }

  func testVoiceTextsForPhasesAndDurations() {
    XCTAssertEqual(
      CardioVoiceText.text(
        for: .phaseStarted(index: 2, count: 9, name: "Belastung", durationSeconds: 240, zoneLowBpm: 160, zoneHighBpm: 172)),
      "Phase 3 von 9, Belastung, 4 Minuten, Ziel 160 bis 172."
    )
    XCTAssertEqual(
      CardioVoiceText.text(
        for: .phaseStarted(index: 0, count: 2, name: "Pause", durationSeconds: 45, zoneLowBpm: nil, zoneHighBpm: nil)),
      "Phase 1 von 2, Pause, 45 Sekunden."
    )
    XCTAssertEqual(CardioVoiceText.durationText(seconds: 90), "1 Minute 30")
    XCTAssertEqual(CardioVoiceText.durationText(seconds: 60), "1 Minute")
    XCTAssertEqual(CardioVoiceText.durationText(seconds: 135), "2 Minuten 15")
  }

  func testVoiceIntervalText() {
    XCTAssertEqual(CardioVoiceText.intervalText(minutes: 12, bpm: 134), "12 Minuten, Puls 134.")
    XCTAssertEqual(CardioVoiceText.intervalText(minutes: 12, bpm: nil), "12 Minuten.")
    XCTAssertEqual(CardioVoiceText.intervalText(minutes: 1, bpm: 90), "1 Minute, Puls 90.")
  }

  func testVoiceScheduleAnnouncesEveryIntervalWithoutCatchUp() {
    var schedule = CardioVoiceSchedule(intervalMinutes: 5, startedAt: start, now: start)
    XCTAssertNil(schedule.due(now: at(299)))
    XCTAssertEqual(schedule.due(now: at(300)), 5)
    XCTAssertNil(schedule.due(now: at(301)))
    // Nach einer Lücke wird nur die letzte fällige Ansage gesprochen.
    XCTAssertEqual(schedule.due(now: at(905)), 15)
    XCTAssertNil(schedule.due(now: at(906)))

    var resumed = CardioVoiceSchedule(intervalMinutes: 5, startedAt: start, now: at(700))
    XCTAssertNil(resumed.due(now: at(701)))
    XCTAssertEqual(resumed.due(now: at(900)), 15)

    var off = CardioVoiceSchedule(intervalMinutes: nil, startedAt: start, now: start)
    XCTAssertNil(off.due(now: at(10_000)))
    var zero = CardioVoiceSchedule(intervalMinutes: 0, startedAt: start, now: start)
    XCTAssertNil(zero.due(now: at(10_000)))
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

  func testPhaseNotificationTexts() {
    let started = CardioAlertMessage.make(
      for: .phaseStarted(index: 2, count: 9, name: "Belastung", durationSeconds: 240, zoneLowBpm: 160, zoneHighBpm: 172),
      zoneLowBpm: nil, zoneHighBpm: nil)
    XCTAssertEqual(started.kind, "phase")
    XCTAssertEqual(started.title, "Phase 3/9 · Belastung 4:00")
    XCTAssertEqual(started.body, "Ziel 160–172")
    XCTAssertTrue(started.playsSound)

    let noZone = CardioAlertMessage.make(
      for: .phaseStarted(index: 0, count: 2, name: "Pause", durationSeconds: 90, zoneLowBpm: nil, zoneHighBpm: nil),
      zoneLowBpm: 120, zoneHighBpm: 140)
    XCTAssertEqual(noZone.title, "Phase 1/2 · Pause 1:30")
    XCTAssertEqual(noZone.body, "")

    let finished = CardioAlertMessage.make(for: .templateFinished, zoneLowBpm: nil, zoneHighBpm: nil)
    XCTAssertEqual(finished.title, "Vorlage beendet")
    XCTAssertEqual(finished.body, "Du kannst beenden oder weiterfahren.")
    XCTAssertEqual(finished.kind, "phase")
    XCTAssertEqual(NativeCardioAlerts.identifier(forKind: "phase"), "com.gainer.mobile.cardio.phase")
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

  func testLiveActivityThrottlePushesPhaseChangesImmediately() {
    var throttle = CardioLiveActivityThrottle()
    XCTAssertTrue(throttle.shouldPush(zoneState: "inZone", bpm: 130, phaseIndex: 1, now: at(0)))
    XCTAssertFalse(throttle.shouldPush(zoneState: "inZone", bpm: 130, phaseIndex: 1, now: at(1)))
    XCTAssertTrue(throttle.shouldPush(zoneState: "inZone", bpm: 130, phaseIndex: 2, now: at(2)))
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

  private func config(
    low: Int64?, high: Int64?, grace: Int64 = 15, repeatEvery: Int64 = 60, warmup: Int64 = 180,
    phases: [PlatformCardioPhase]? = nil, voiceIntervalMinutes: Int64? = nil
  ) -> PlatformCardioMonitoringConfig {
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
      zoneHighBpm: high,
      phases: phases,
      voiceEnabled: voiceIntervalMinutes == nil ? nil : true,
      voiceIntervalMinutes: voiceIntervalMinutes
    )
  }

  private func phase(
    _ offset: Int64, _ duration: Int64, low: Int64? = nil, high: Int64? = nil
  ) -> PlatformCardioPhase {
    PlatformCardioPhase(
      startOffsetSeconds: offset, durationSeconds: duration, name: "Phase", zoneLowBpm: low, zoneHighBpm: high)
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

  func testCardioPhaseValidation() {
    func validate(_ phases: [PlatformCardioPhase]?, voice: Int64? = nil) throws {
      try GainerMobilePlatform.validate(
        cardioConfig: config(low: nil, high: nil, phases: phases, voiceIntervalMinutes: voice))
    }
    XCTAssertNoThrow(try validate(nil))
    XCTAssertNoThrow(try validate([]))
    XCTAssertNoThrow(try validate([phase(0, 600, low: 110, high: 130), phase(600, 30), phase(700, 3600)]))
    // Dauer außerhalb 30–3600.
    XCTAssertThrowsError(try validate([phase(0, 29)]))
    XCTAssertThrowsError(try validate([phase(0, 3601)]))
    // Überlappung und falsche Reihenfolge.
    XCTAssertThrowsError(try validate([phase(0, 600), phase(599, 60)]))
    XCTAssertThrowsError(try validate([phase(600, 60), phase(0, 60)]))
    XCTAssertThrowsError(try validate([phase(-1, 60)]))
    // Zone: beide oder keine, 40–230, von < bis.
    XCTAssertThrowsError(try validate([phase(0, 60, low: 120)]))
    XCTAssertThrowsError(try validate([phase(0, 60, low: 140, high: 120)]))
    XCTAssertThrowsError(try validate([phase(0, 60, low: 30, high: 120)]))
    XCTAssertThrowsError(try validate([phase(0, 60, low: 120, high: 231)]))
    // Höchstens 30 Phasen.
    let thirty = (0..<30).map { phase(Int64($0) * 60, 60) }
    XCTAssertNoThrow(try validate(thirty))
    XCTAssertThrowsError(try validate(thirty + [phase(1800, 60)]))
    // Sprachintervall 0–60.
    XCTAssertNoThrow(try validate(nil, voice: 0))
    XCTAssertNoThrow(try validate(nil, voice: 60))
    XCTAssertThrowsError(try validate(nil, voice: 61))
    XCTAssertThrowsError(try validate(nil, voice: -1))
  }
}
