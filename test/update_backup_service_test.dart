import 'dart:io';

import 'package:aperture_grafik/domain/update_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'creates a durable JSON backup and retains only the newest copies',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aperture_backups_',
      );
      addTearDown(() => directory.delete(recursive: true));
      const service = UpdateBackupService(maxBackups: 2);

      final first = await service.createBackup(
        documentsDirectory: directory,
        contents: '{"revision":1}',
        timestamp: DateTime.utc(2026, 10, 2, 10),
      );
      await service.createBackup(
        documentsDirectory: directory,
        contents: '{"revision":2}',
        timestamp: DateTime.utc(2026, 10, 2, 11),
      );
      final latest = await service.createBackup(
        documentsDirectory: directory,
        contents: '{"revision":3}',
        timestamp: DateTime.utc(2026, 10, 2, 12),
      );

      expect(await File(first.path).exists(), isFalse);
      expect(await latest.readAsString(), '{"revision":3}');
      final backups = await Directory(
        '${directory.path}${Platform.pathSeparator}backups',
      ).list().where((entry) => entry.path.endsWith('.json')).toList();
      expect(backups, hasLength(2));
      expect(backups.any((entry) => entry.path == latest.path), isTrue);
    },
  );
}
