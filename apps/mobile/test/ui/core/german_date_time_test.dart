import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/german_date_time.dart';

void main() {
  test('formats local time German without seconds or zone', () {
    expect(
      formatGermanDateTime(DateTime(2026, 10, 6, 4, 3, 9, 123)),
      '06.10.2026, 04:03',
    );
  });
}
