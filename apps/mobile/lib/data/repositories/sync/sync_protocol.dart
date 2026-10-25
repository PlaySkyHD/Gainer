/// Sync-Protokoll dieser App, für jede Registrierung, jeden Push und Pull.
///
/// Trainingsoperationen verlangen Version 3, die Wassermenge Version 4;
/// sonst antwortet der Server mit `upgrade_required`. Alle Wege (Sync und
/// Geräteübergabe) nutzen diese eine Konstante, damit keine Registrierung
/// die gespeicherte Version des Geräts zurücksetzt.
const nativeSyncProtocolVersion = 4;
