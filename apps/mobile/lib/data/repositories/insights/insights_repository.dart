import '../../models/api/api_models.dart';
import '../../services/api/api_client.dart';

class InsightsRepository {
  const InsightsRepository(this.api);

  final ApiClient api;

  Future<ApiDashboardInsights> loadDashboard({int days = 30}) =>
      api.getDashboardInsights(days: days);
}

class CoachRepository {
  const CoachRepository(this.api);

  final ApiClient api;

  Future<ApiCoachResponse> ask(String question) => api.askCoach(question);
}
