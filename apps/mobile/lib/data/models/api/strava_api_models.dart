/// Strava-Verbindung des Kontos; enthält nie Tokens.
class ApiStravaStatus {
  const ApiStravaStatus({
    required this.configured,
    required this.connected,
    required this.needsReconnect,
    required this.athleteName,
    required this.exportCardio,
    required this.exportStrength,
  });

  factory ApiStravaStatus.fromJson(Map<String, dynamic> json) =>
      ApiStravaStatus(
        configured: json['configured'] as bool? ?? false,
        connected: json['connected'] as bool? ?? false,
        needsReconnect: json['needsReconnect'] as bool? ?? false,
        athleteName: json['athleteName'] as String?,
        exportCardio: json['exportCardio'] as bool? ?? false,
        exportStrength: json['exportStrength'] as bool? ?? false,
      );

  /// Der Server hat Client-Id und Secret; sonst ist Strava nicht verfügbar.
  final bool configured;
  final bool connected;

  /// Strava hat den Zugriff abgelehnt; der Nutzer muss neu verbinden.
  final bool needsReconnect;
  final String? athleteName;
  final bool exportCardio;
  final bool exportStrength;
}

/// Art einer exportierten Einheit; [wireName] steht im Pfad.
enum StravaExportKind {
  cardio('cardio'),
  strength('strength');

  const StravaExportKind(this.wireName);

  final String wireName;
}

enum StravaExportStatus { pending, processing, completed, failed }

class ApiStravaExport {
  const ApiStravaExport({
    required this.status,
    required this.activityId,
    required this.errorCode,
  });

  factory ApiStravaExport.fromJson(Map<String, dynamic> json) =>
      ApiStravaExport(
        status: switch (json['status']) {
          'processing' => StravaExportStatus.processing,
          'completed' => StravaExportStatus.completed,
          'failed' => StravaExportStatus.failed,
          _ => StravaExportStatus.pending,
        },
        activityId: (json['activityId'] as num?)?.toInt(),
        errorCode: json['errorCode'] as String?,
      );

  final StravaExportStatus status;
  final int? activityId;
  final String? errorCode;

  bool get isSending =>
      status == StravaExportStatus.pending ||
      status == StravaExportStatus.processing;
}
