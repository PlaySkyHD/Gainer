import 'package:gainer_mobile/data/models/api/strava_api_models.dart';
import 'package:gainer_mobile/data/repositories/strava/strava_service.dart';

ApiStravaStatus stravaStatus({
  bool configured = true,
  bool connected = true,
  bool needsReconnect = false,
  String? athleteName = 'Nic M',
  bool exportCardio = true,
  bool exportStrength = false,
}) => ApiStravaStatus(
  configured: configured,
  connected: connected,
  needsReconnect: needsReconnect,
  athleteName: athleteName,
  exportCardio: exportCardio,
  exportStrength: exportStrength,
);

class FakeStravaService implements StravaService {
  FakeStravaService(this.current);

  ApiStravaStatus current;
  StravaConnectResult connectResult = StravaConnectResult.connected;
  ApiStravaStatus? afterConnect;
  bool failSettings = false;
  int connects = 0;
  int disconnects = 0;
  final settings = <(bool, bool)>[];
  final exports = <String, ApiStravaExport>{};
  final requested = <String>[];

  /// Status, den der Server nach einer Anforderung meldet.
  StravaExportStatus requestedStatus = StravaExportStatus.pending;

  @override
  Future<ApiStravaStatus> status() async => current;

  @override
  Future<StravaConnectResult> connect() async {
    connects++;
    if (connectResult == StravaConnectResult.connected) {
      current = afterConnect ?? stravaStatus();
    }
    return connectResult;
  }

  @override
  Future<ApiStravaStatus> updateSettings({
    required bool exportCardio,
    required bool exportStrength,
  }) async {
    if (failSettings) throw StateError('offline');
    settings.add((exportCardio, exportStrength));
    current = stravaStatus(
      athleteName: current.athleteName,
      exportCardio: exportCardio,
      exportStrength: exportStrength,
    );
    return current;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    current = stravaStatus(connected: false, athleteName: null);
  }

  @override
  Future<ApiStravaExport?> export(
    StravaExportKind kind,
    String resourceId,
  ) async => exports[resourceId];

  @override
  Future<ApiStravaExport> requestExport(
    StravaExportKind kind,
    String resourceId,
  ) async {
    requested.add(resourceId);
    final export = ApiStravaExport(
      status: requestedStatus,
      activityId: null,
      errorCode: null,
    );
    exports[resourceId] = export;
    return export;
  }
}
