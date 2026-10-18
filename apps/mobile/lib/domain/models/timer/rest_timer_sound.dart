/// Ablauftöne des Pausentimers. [id] gilt auch in den Einstellungen und in der
/// iOS-Umsetzung; `system` ist der iOS-Standardton.
class RestTimerSound {
  const RestTimerSound(this.id, this.label);

  final String id;
  final String label;

  static const defaultId = 'digital_alarm';

  static const all = [
    RestTimerSound('digital_alarm', 'Digitaler Wecker'),
    RestTimerSound('boxing_bell', 'Boxglocke'),
    RestTimerSound('radar', 'Radar'),
    RestTimerSound('bike_bell', 'Fahrradklingel'),
    RestTimerSound('gong', 'Gong'),
    RestTimerSound('chime', 'Glockenspiel'),
    RestTimerSound('pulse', 'Signal'),
    RestTimerSound('system', 'System'),
  ];

  /// Gültige Id; unbekannte oder fehlende Werte ergeben den Standardton.
  static String resolveId(Object? id) =>
      all.any((sound) => sound.id == id) ? id! as String : defaultId;
}
