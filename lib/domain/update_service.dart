import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class AppReleaseInfo {
  const AppReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.downloadUrl,
    this.sizeBytes,
    this.publishedAt,
    this.isNewer = false,
  });

  final String tag;
  final String version;
  final String notes;
  final String downloadUrl;
  final int? sizeBytes;
  final DateTime? publishedAt;
  final bool isNewer;

  String get displaySize {
    if (sizeBytes == null || sizeBytes! <= 0) return '';
    final mb = sizeBytes! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} МБ';
  }
}

class DownloadProgress {
  const DownloadProgress({
    required this.fraction,
    required this.receivedBytes,
    required this.totalBytes,
    this.remainingSeconds,
  });

  final double fraction;
  final int receivedBytes;
  final int totalBytes;
  final int? remainingSeconds;

  String etaString(bool isRu) {
    if (remainingSeconds == null || remainingSeconds! <= 0) return '';
    if (remainingSeconds! >= 60) {
      final mins = (remainingSeconds! / 60).ceil();
      return isRu ? '$mins мин' : '$mins min';
    }
    return isRu ? '$remainingSeconds сек' : '$remainingSeconds sec';
  }
}

class SemVer {
  const SemVer({
    required this.major,
    required this.minor,
    required this.patch,
    this.build = 0,
  });

  final int major;
  final int minor;
  final int patch;
  final int build;

  static SemVer parse(String raw) {
    final match = RegExp(
      r'^[vV]?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$',
    ).firstMatch(raw.trim());
    if (match == null) {
      throw FormatException('Invalid application version: $raw');
    }
    return SemVer(
      major: int.parse(match[1]!),
      minor: int.parse(match[2]!),
      patch: int.parse(match[3]!),
      build: int.tryParse(match[4] ?? '') ?? 0,
    );
  }

  bool isNewerThan(SemVer other) {
    if (major != other.major) return major > other.major;
    if (minor != other.minor) return minor > other.minor;
    if (patch != other.patch) return patch > other.patch;
    return build > other.build;
  }

  @override
  String toString() => '$major.$minor.$patch${build > 0 ? '+$build' : ''}';
}

class UpdateService {
  const UpdateService();

  // GitHub Releases is the single source of app updates.
  static const String githubRepo = 'santiyastudio-lgtm/aperture-grafik';

  Future<AppReleaseInfo?> checkForUpdates({
    required String currentVersion,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      try {
        final uri = Uri.parse(
          'https://api.github.com/repos/$githubRepo/releases/latest',
        );
        final response = await httpClient
            .get(
              uri,
              headers: {
                'Accept': 'application/vnd.github.v3+json',
                'User-Agent': 'ApertureGrafik-Updater',
              },
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final release = _parseGithubRelease(json, currentVersion);
          if (release != null) return release;
        }
      } catch (_) {}

      return null;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  AppReleaseInfo? _parseGithubRelease(
    Map<String, dynamic> json,
    String currentVersion,
  ) {
    final tagName = json['tag_name'] as String? ?? '';
    final body = json['body'] as String? ?? '';
    final publishedAtStr = json['published_at'] as String?;
    final publishedAt = publishedAtStr != null
        ? DateTime.tryParse(publishedAtStr)
        : null;

    final assets = json['assets'] as List<dynamic>? ?? <dynamic>[];
    String? apkUrl;
    int? apkSize;

    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          apkSize = (asset['size'] as num?)?.toInt();
          break;
        }
      }
    }

    if (apkUrl == null || apkUrl.isEmpty) {
      apkUrl =
          'https://github.com/$githubRepo/releases/download/$tagName/aperture-grafik.apk';
    }

    final remoteSemver = SemVer.parse(tagName);
    final localSemver = SemVer.parse(currentVersion);
    final isNewer = remoteSemver.isNewerThan(localSemver);

    return AppReleaseInfo(
      tag: tagName,
      version: remoteSemver.toString(),
      notes: body,
      downloadUrl: apkUrl,
      sizeBytes: apkSize,
      publishedAt: publishedAt,
      isNewer: isNewer,
    );
  }

  Stream<DownloadProgress> downloadApk({
    required String downloadUrl,
    required String targetPath,
    http.Client? client,
  }) async* {
    final httpClient = client ?? http.Client();
    var finalReceivedBytes = 0;
    var finalTotalBytes = 0;
    try {
      var currentUrl = Uri.parse(downloadUrl);
      _validateDownloadUri(currentUrl);
      http.StreamedResponse? streamedResponse;
      var redirectCount = 0;

      while (redirectCount <= 6) {
        final request = http.Request('GET', currentUrl);
        request.headers['User-Agent'] = 'ApertureGrafik-Updater';
        final response = await httpClient.send(request);

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location != null && location.isNotEmpty) {
            currentUrl = currentUrl.resolve(location);
            _validateDownloadUri(currentUrl);
            redirectCount++;
            continue;
          }
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            'Failed to download update: HTTP ${response.statusCode}',
          );
        }

        streamedResponse = response;
        break;
      }

      if (streamedResponse == null) {
        throw const HttpException(
          'Too many redirects while downloading update',
        );
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      var receivedBytes = 0;
      finalTotalBytes = totalBytes;
      final startTime = DateTime.now();

      final file = File(targetPath);
      if (await file.exists()) {
        await file.delete();
      }
      await file.create(recursive: true);

      final sink = file.openWrite();
      var completed = false;
      try {
        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;

          final fraction = totalBytes > 0 ? (receivedBytes / totalBytes) : -1.0;
          final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
          int? remainingSec;
          if (elapsedMs > 400 && fraction > 0.02 && fraction < 1.0) {
            final totalEstimatedMs = elapsedMs / fraction;
            remainingSec = ((totalEstimatedMs - elapsedMs) / 1000).round();
          }

          yield DownloadProgress(
            fraction: fraction,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            remainingSeconds: remainingSec,
          );
        }
        await sink.flush();
        completed = true;
      } finally {
        await sink.close();
        if (!completed) {
          try {
            if (await file.exists()) await file.delete();
          } on FileSystemException {
            // A failed download must not mask its original network error.
          }
        }
      }
      finalReceivedBytes = receivedBytes;
      if (totalBytes > 0 && receivedBytes != totalBytes) {
        try {
          await file.delete();
        } on FileSystemException {
          // The size mismatch remains the actionable error.
        }
        throw HttpException(
          'Incomplete update download: received $receivedBytes of $totalBytes bytes',
        );
      }
      if (receivedBytes == 0) {
        try {
          await file.delete();
        } on FileSystemException {
          // The empty response remains the actionable error.
        }
        throw const HttpException('Update download was empty');
      }
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }

    yield DownloadProgress(
      fraction: 1.0,
      receivedBytes: finalReceivedBytes,
      totalBytes: finalTotalBytes > 0 ? finalTotalBytes : finalReceivedBytes,
      remainingSeconds: 0,
    );
  }

  void _validateDownloadUri(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw HttpException('Update downloads and redirects must use HTTPS');
    }
  }

  Future<String> getLocalApkPath() async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/update_aperture_grafik.apk';
  }

  Future<OpenResult> installApk(String filePath) async {
    return OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );
  }
}
