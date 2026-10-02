import 'dart:io';

/// Keeps a durable local snapshot before handing an app update to Android.
class UpdateBackupService {
  const UpdateBackupService({this.maxBackups = 8}) : assert(maxBackups > 0);

  final int maxBackups;

  Future<File> createBackup({
    required Directory documentsDirectory,
    required String contents,
    DateTime? timestamp,
  }) async {
    final backupDirectory = Directory(
      '${documentsDirectory.path}${Platform.pathSeparator}backups',
    );
    await backupDirectory.create(recursive: true);

    final stamp = (timestamp ?? DateTime.now())
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('+', '_plus_');
    final destination = File(
      '${backupDirectory.path}${Platform.pathSeparator}'
      'aperture_grafik_pre_update_$stamp.json',
    );
    final temporary = File('${destination.path}.tmp');
    try {
      await temporary.writeAsString(contents, flush: true);
      final saved = await temporary.rename(destination.path);
      try {
        await _pruneBackups(backupDirectory);
      } on FileSystemException {
        // Backup cleanup is best-effort; the new copy is already durable.
      }
      return saved;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> _pruneBackups(Directory directory) async {
    final backups = <File>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File &&
          entry.path.endsWith('.json') &&
          entry.uri.pathSegments.last.startsWith(
            'aperture_grafik_pre_update_',
          )) {
        backups.add(entry);
      }
    }
    backups.sort((a, b) => b.path.compareTo(a.path));
    for (final file in backups.skip(maxBackups)) {
      try {
        await file.delete();
      } on FileSystemException {
        // A cleanup failure must not invalidate the backup just written.
      }
    }
  }
}
