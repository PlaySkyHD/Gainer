import '../../models/api/strava_api_models.dart';
import '../../services/api/api_client.dart';
import '../../services/platform/pigeon_web_authentication_platform.dart';
import '../../services/platform/platform_ports.dart';

/// Ergebnis von „Mit Strava verbinden“.
enum StravaConnectResult {
  connected,

  /// In Strava abgelehnt oder ohne Recht zum Hochladen bestätigt.
  denied,
  cancelled,
  failed,
}

/// Strava-Funktionen des Kontos. Tokens liegen nur auf dem Server.
abstract interface class StravaService {
  Future<ApiStravaStatus> status();

  /// Öffnet die Strava-Zustimmung im Anmelde-Sheet.
  Future<StravaConnectResult> connect();

  Future<ApiStravaStatus> updateSettings({
    required bool exportCardio,
    required bool exportStrength,
  });

  Future<void> disconnect();

  Future<ApiStravaExport?> export(StravaExportKind kind, String resourceId);

  Future<ApiStravaExport> requestExport(
    StravaExportKind kind,
    String resourceId,
  );
}

class ApiStravaService implements StravaService {
  ApiStravaService({required this.api, WebAuthenticationPlatform? web})
    : web = web ?? PigeonWebAuthenticationPlatform();

  /// Schema und Host der Rückleitung, die der Server nach dem Callback sendet.
  static const callbackScheme = 'gainer';
  static const callbackHost = 'strava';

  final ApiClient api;
  final WebAuthenticationPlatform web;

  @override
  Future<ApiStravaStatus> status() => api.getStravaStatus();

  @override
  Future<StravaConnectResult> connect() async {
    final url = await api.beginStravaAuthorization();
    final callback = await web.authenticate(
      url,
      callbackScheme: callbackScheme,
    );
    if (callback == null) return StravaConnectResult.cancelled;
    return parseCallback(callback);
  }

  /// `gainer://strava?result=connected|denied|failed`.
  static StravaConnectResult parseCallback(Uri callback) {
    if (callback.scheme != callbackScheme || callback.host != callbackHost) {
      return StravaConnectResult.failed;
    }
    return switch (callback.queryParameters['result']) {
      'connected' => StravaConnectResult.connected,
      'denied' => StravaConnectResult.denied,
      _ => StravaConnectResult.failed,
    };
  }

  @override
  Future<ApiStravaStatus> updateSettings({
    required bool exportCardio,
    required bool exportStrength,
  }) => api.updateStravaSettings(
    exportCardio: exportCardio,
    exportStrength: exportStrength,
  );

  @override
  Future<void> disconnect() => api.disconnectStrava();

  @override
  Future<ApiStravaExport?> export(StravaExportKind kind, String resourceId) =>
      api.getStravaExport(kind, resourceId);

  @override
  Future<ApiStravaExport> requestExport(
    StravaExportKind kind,
    String resourceId,
  ) => api.requestStravaExport(kind, resourceId);
}
