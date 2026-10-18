import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/body/health/health_review_view_model.dart';

void main() {
  test('Plattformfehler werden als verständlicher Text gezeigt', () {
    expect(
      healthErrorMessage(PlatformException(code: 'health_invalid_range')),
      contains('Zeitraum'),
    );
    expect(
      healthErrorMessage(PlatformException(code: 'health_unavailable')),
      'Apple Health ist auf diesem Gerät nicht verfügbar.',
    );
    expect(
      healthErrorMessage(
        PlatformException(code: 'health_write_permission_not_granted'),
      ),
      contains('Health-Einstellungen'),
    );
    expect(
      healthErrorMessage(PlatformException(code: 'health_query_failed')),
      contains('erneut'),
    );
    expect(
      healthErrorMessage(StateError('Nicht angemeldet.')),
      'Nicht angemeldet.',
    );
    expect(healthErrorMessage(ArgumentError('x')), contains('x'));
  });
}
