import Foundation

/// Ein ausgewerteter Messwert der Heart Rate Measurement Characteristic (0x2A37).
struct HeartRateMeasurement: Equatable {
  let bpm: Int
  /// RR-Intervalle in ms, umgerechnet aus 1/1024 s und gerundet.
  let rrIntervalsMs: [Int]
}

/// Reine Auswertung der Bluetooth-GATT-Daten eines Pulsgurts, ohne CoreBluetooth.
enum HeartRateMeasurementParser {
  /// Flags: Bit 0 = bpm als UInt16, Bit 3 = Energy Expended (2 Byte) folgt,
  /// Bit 4 = RR-Intervalle (UInt16, 1/1024 s) folgen. Alles little endian.
  /// Fehlerhafte oder zu kurze Daten ergeben nil.
  static func parse(_ bytes: [UInt8]) -> HeartRateMeasurement? {
    guard let flags = bytes.first else { return nil }
    var index = 1

    let bpm: Int
    if flags & 0x01 != 0 {
      guard bytes.count >= index + 2 else { return nil }
      bpm = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
      index += 2
    } else {
      guard bytes.count >= index + 1 else { return nil }
      bpm = Int(bytes[index])
      index += 1
    }

    if flags & 0x08 != 0 {
      guard bytes.count >= index + 2 else { return nil }
      index += 2
    }

    var intervals: [Int] = []
    if flags & 0x10 != 0 {
      let remaining = bytes.count - index
      // Ein halbes RR-Intervall am Ende ist ein Übertragungsfehler.
      guard remaining >= 0, remaining % 2 == 0 else { return nil }
      while index + 1 < bytes.count {
        let raw = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
        intervals.append(rrMilliseconds(fromRaw: raw))
        index += 2
      }
    }
    return HeartRateMeasurement(bpm: bpm, rrIntervalsMs: intervals)
  }

  /// 1/1024 s in ms, auf ganze Millisekunden gerundet (1024 ergibt 1000).
  static func rrMilliseconds(fromRaw raw: Int) -> Int {
    (raw * 1000 + 512) / 1024
  }

  /// Battery Level (0x2A19): ein Byte, 0–100 Prozent. Alles andere ergibt nil.
  static func parseBattery(_ bytes: [UInt8]) -> Int? {
    guard let level = bytes.first, level <= 100 else { return nil }
    return Int(level)
  }
}
