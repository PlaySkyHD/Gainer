import '../../../data/repositories/body/body_repository.dart';
import '../../../data/repositories/cardio/cardio_repository.dart';
import '../../../data/repositories/health/cardio_health_exporter.dart';
import '../../../data/repositories/strava/strava_service.dart';
import 'cardio_session_controller.dart';

/// Abhängigkeiten der Cardio-Oberfläche eines Kontos.
class CardioFeature {
  const CardioFeature({
    required this.repository,
    required this.session,
    required this.health,
    this.body,
    this.strava,
  });

  final CardioRepository repository;
  final CardioSessionController session;
  final CardioHealthExporter health;

  /// Check-in des Kontos für die HRV-Messung; ohne Wert entfällt sie.
  final BodyRepository? body;

  /// Strava des Kontos; null ohne Verbindung zum Server.
  final StravaService? strava;
}
