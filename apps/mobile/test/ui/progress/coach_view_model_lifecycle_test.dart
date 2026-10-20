import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/ui/features/coach/coach_view_model.dart';
import 'package:gainer_mobile/ui/features/progress/progress_view_model.dart';

class _PendingApiClient extends ApiClient {
  _PendingApiClient(this.pending)
    : super(
        configuration: ApiConfiguration(
          apiOrigin: Uri.parse('http://127.0.0.1:5099'),
          allowInsecureLoopbackForDevelopment: true,
        ),
      );

  final Completer<void> pending;

  @override
  Future<ApiDashboardInsights> getDashboardInsights({
    int days = 30,
    DateTime? through,
  }) async {
    await pending.future;
    throw StateError('request failed after disposal');
  }

  @override
  Future<ApiCoachResponse> askCoach(String question) async {
    await pending.future;
    throw StateError('request failed after disposal');
  }
}

void main() {
  test(
    'progress load finishing after dispose does not notify listeners',
    () async {
      final pending = Completer<void>();
      final api = _PendingApiClient(pending);
      final model = ProgressViewModel(InsightsRepository(api));
      final load = model.load();

      model.dispose();
      pending.complete();
      await load;
      api.close();
    },
  );

  test(
    'coach request finishing after dispose does not notify listeners',
    () async {
      final pending = Completer<void>();
      final api = _PendingApiClient(pending);
      final model = CoachViewModel(CoachRepository(api));
      final ask = model.ask('How is my progress?');

      model.dispose();
      pending.complete();
      await ask;
      api.close();
    },
  );
}
