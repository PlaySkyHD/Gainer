import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

void main() {
  test(
    'capture errors are shown in German instead of the raw exception',
    () async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final capture = _FailingCapture();
      final viewModel = NutritionViewModel(
        repository: NutritionRepository(
          store: LocalSyncStore(
            database: database,
            accountId: '00000000-0000-4000-8000-000000000004',
          ),
          capture: capture,
          clock: () => DateTime.utc(2026, 10, 12, 10),
        ),
        localDate: '2026-10-12',
      );
      addTearDown(viewModel.dispose);

      for (final (code, expected) in [
        ('capture_in_progress', 'Die Kamera ist noch geöffnet.'),
        (
          'camera_permission_denied',
          'Erlaube den Zugriff in den iOS-Einstellungen',
        ),
        ('something_new', 'Die Aufnahme ist fehlgeschlagen.'),
      ]) {
        capture.code = code;
        await viewModel.lookupBarcode();
        expect(viewModel.errorMessage, contains(expected));
        expect(viewModel.errorMessage, isNot(contains('PlatformException')));
        expect(viewModel.errorOperation, NutritionErrorOperation.barcode);
      }
    },
  );
}

class _FailingCapture implements CapturePlatform {
  String code = 'capture_in_progress';

  @override
  Future<String?> scanBarcode() async => throw PlatformException(
    code: code,
    message: 'Another capture flow is already active.',
  );

  @override
  Future<CapturedImage?> capturePhoto() => throw UnimplementedError();

  @override
  Future<CapturedImage?> chooseImage() => throw UnimplementedError();
}
