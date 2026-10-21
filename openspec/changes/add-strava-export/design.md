# Design

## D1 OAuth über das Backend

Strava verlangt für den Token-Tausch das Client-Secret. Deshalb läuft der Fluss über den Server:

1. Die App ruft `POST /api/v1/integrations/strava/authorization` und erhält die Strava-URL. Der `state` ist mit Data Protection verschlüsselt, enthält die UserId, gilt 10 Minuten und wird nur einmal angenommen.
2. Die App öffnet die URL in `ASWebAuthenticationSession` mit dem Callback-Schema `gainer`.
3. Strava leitet auf `GET /api/v1/integrations/strava/callback` (anonym). Der Server prüft `state` und Scope, tauscht den Code, speichert die Verbindung und leitet auf `gainer://strava?result=connected|denied|failed` weiter.
4. Die Session fängt die Weiterleitung ab, die App lädt den Status neu.

Die Callback-Domain der Strava-App ist die API-Domain (`gainer.markfort.xyz`).

## D2 Datenmodell

- `integrations.strava_connections` (Schlüssel UserId):
  - Athlet (Id, Name), Scope, Access- und Refresh-Token (Data Protection, Zweck `Gainer.Strava.Tokens`), Ablauf.
  - `CardioExportSinceUtc` und `StrengthExportSinceUtc`: null = Art aus, sonst Zeitpunkt des Einschaltens.
  - `NeedsReconnect`, wenn Strava Refresh oder Zugriff ablehnt.
- `integrations.strava_exports` (eindeutig je UserId, Art, ResourceId, AthleteId): Status `Pending`, `Processing`, `Completed`, `Failed`; Upload- und Aktivitäts-Id, Versuche, nächster Versuch, Fehlercode.

Beide sind `UserOwnedEntity` und hängen per Cascade am Konto.

## D3 Export als Ledger statt Hook im Sync

Der Worker gleicht regelmäßig ab, statt in den Sync-Pfad einzugreifen. Ein Durchlauf je Nutzer mit Verbindung:

1. **Einreihen:** beendete Einheiten der eingeschalteten Art, die nach dem Einschalten endeten, seit 2 Minuten unverändert sind und noch keinen Ledger-Eintrag für diesen Athleten haben.
2. **Senden:** fällige `Pending`-Einträge (höchstens 5 je Durchlauf).
   - Beide Arten als TCX-Upload mit `external_id = gainer-<art>-<id>`. Die Zeiten stehen in UTC, Strava rechnet mit der Zeitzone des Athleten. Der Server kennt die Zeitzone des Nutzers nicht, darum kein `POST /activities` mit `start_date_local`.
   - Kraft danach per `PUT /activities/{id}` auf `sport_type = WeightTraining`.
3. **Prüfen:** `Processing`-Uploads abfragen. „duplicate of activity N“ gilt als erledigt.

Fehler:

- Netzwerk und 5xx: Wiederholung mit Backoff (1, 5, 15, 60 min), nach 6 Versuchen `Failed`.
- 429: Pause für diesen Nutzer 15 Minuten.
- 401 oder abgelehnter Refresh: `NeedsReconnect`, keine weiteren Versuche bis zur neuen Verbindung.
- Gelöschte Einheit vor dem Senden: Eintrag wird entfernt.

Der Worker läuft im Nutzerkontext (`BackgroundUserScope`), damit die Abfragefilter der Nutzerisolation gelten. Nur die Liste der verbundenen Nutzer wird ohne Filter gelesen.

Eine manuelle Anforderung setzt den Eintrag auf `Pending` und weckt den Worker.

## D4 Inhalt der Aktivitäten

- **Cardio:**
  - Name ist der Vorlagenname oder „Rad-Ergometer“.
  - TCX `Sport="Biking"`, ein Trackpoint je Pulswert ungleich 0. Die Distanz wird linear über die Dauer verteilt.
  - Kalorien stehen in der Runde.
  - Beschreibung: Notizen, Zielbereich und Ø-Leistung, falls vorhanden.
- **Kraft:**
  - Name ist der Workout-Titel.
  - TCX `Sport="Other"` mit Trackpoints an Start und Ende.
  - Dauer von Start bis Ende.
  - Beschreibung: je Übung „Name: 3 × 8 · 80 kg“, Aufwärmsätze ausgenommen.

## D5 App

- „Mehr → Strava“ zeigt je nach Zustand:
  - nicht eingerichtet: Hinweis, keine Aktion;
  - nicht verbunden: „Mit Strava verbinden“;
  - verbunden: Athlet, Schalter „Cardio-Einheiten“ und „Krafttraining“, „Verbindung trennen“;
  - `NeedsReconnect`: Hinweis und „Erneut verbinden“.
- Offline sind die Aktionen deaktiviert und der Grund steht darunter.
- Die Cardio-Detailansicht zeigt eine Zeile „Strava“: „Gesendet“, „Wird gesendet“, „Fehlgeschlagen“ oder „An Strava senden“. Die Zeile erscheint nur, wenn Strava verbunden und die Einheit synchronisiert ist.

## D6 Konfiguration

- `Strava:ClientId`, `Strava:ClientSecret` (oder `Strava:ClientSecretFile`), `Strava:CallbackUrl`. Compose liest sie aus `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET` und `STRAVA_CALLBACK_URL` in `/etc/gainer/deployment.env`.
- `Strava:ApiBaseUrl` ist einstellbar, weil Strava die API ab Januar 2027 unter `https://api-v3.strava.com/` anbietet.
- Fehlen Client-Id oder Secret, ist die Funktion aus. Der Worker bleibt dann untätig und die App erklärt den Grund.
