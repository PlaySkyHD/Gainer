import '../../../data/repositories/cardio/cardio_repository.dart';
import '../../../data/repositories/health/cardio_health_exporter.dart';
import 'cardio_session_controller.dart';

/// Abhängigkeiten der Cardio-Oberfläche eines Kontos.
class CardioFeature {
  const CardioFeature({
    required this.repository,
    required this.session,
    required this.health,
  });

  final CardioRepository repository;
  final CardioSessionController session;
  final CardioHealthExporter health;
}
