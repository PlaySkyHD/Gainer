import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../services/api/api_client.dart';
import '../../services/platform/pigeon_file_share_platform.dart';
import '../../services/platform/platform_ports.dart';

/// Export aller eigenen Daten als Datei über das Teilen-Sheet.
abstract interface class DataExportService {
  /// Lädt den Export, öffnet das Teilen-Sheet und löscht die Datei danach.
  Future<void> exportAndShare();
}

class ApiDataExportService implements DataExportService {
  ApiDataExportService({
    required this.api,
    FileSharePlatform? share,
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
  }) : share = share ?? PigeonFileSharePlatform(),
       _directory = directory ?? getTemporaryDirectory,
       _clock = clock ?? DateTime.now;

  final ApiClient api;
  final FileSharePlatform share;
  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;

  @override
  Future<void> exportAndShare() async {
    final data = await api.getAccountExport();
    final folder = Directory(p.join((await _directory()).path, 'export'));
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, fileName(_clock())));
    try {
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );
      await share.shareFile(file.path);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  /// `gainer-export-2026-10-24.json` nach lokalem Datum.
  static String fileName(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'gainer-export-${now.year}-${two(now.month)}-${two(now.day)}.json';
  }
}
