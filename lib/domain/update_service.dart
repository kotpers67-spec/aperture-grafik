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
    var cleaned = raw.trim();
    if (cleaned.startsWith('v') || cleaned.startsWith('V')) {
      cleaned = cleaned.substring(1);
    }

    var buildNumber = 0;
    if (cleaned.contains('+')) {
      final parts = cleaned.split('+');
      cleaned = parts[0];
      buildNumber = int.tryParse(parts[1]) ?? 0;
    }

    final segments = cleaned.split('.');
    final maj = segments.isNotEmpty ? int.tryParse(segments[0]) ?? 0 : 0;
    final min = segments.length > 1 ? int.tryParse(segments[1]) ?? 0 : 0;
    final pat = segments.length > 2 ? int.tryParse(segments[2]) ?? 0 : 0;

    return SemVer(
      major: maj,
      minor: min,
      patch: pat,
      build: buildNumber,
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

  // Primary: GitLab (public project & generic package registry)
  static const String gitlabProject = 'santiyastudio%2Faperture-grafik';
  // Secondary: GitHub (backup mirror)
  static const String githubRepo = 'santiyastudio-lgtm/aperture-grafik';

  Future<AppReleaseInfo?> checkForUpdates({
    required String currentVersion,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      // 1. Primary: Try GitLab Releases API
      try {
        final uri = Uri.parse('https://gitlab.com/api/v4/projects/$gitlabProject/releases/permalink/latest');
        final response = await httpClient.get(
          uri,
          headers: {
            'User-Agent': 'ApertureGrafik-Updater',
          },
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final release = _parseGitlabRelease(json, currentVersion);
          if (release != null) return release;
        }
      } catch (_) {
        // Fallback to GitLab list
        try {
          final uri = Uri.parse('https://gitlab.com/api/v4/projects/$gitlabProject/releases?per_page=1');
          final response = await httpClient.get(
            uri,
            headers: {'User-Agent': 'ApertureGrafik-Updater'},
          ).timeout(const Duration(seconds: 8));

          if (response.statusCode == 200) {
            final list = jsonDecode(response.body) as List<dynamic>;
            if (list.isNotEmpty && list.first is Map<String, dynamic>) {
              final release = _parseGitlabRelease(list.first as Map<String, dynamic>, currentVersion);
              if (release != null) return release;
            }
          }
        } catch (_) {}
      }

      // 2. Secondary Fallback: Try GitHub Releases API
      try {
        final uri = Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest');
        final response = await httpClient.get(
          uri,
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'ApertureGrafik-Updater',
          },
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final release = _parseGithubRelease(json, currentVersion);
          if (release != null) return release;
        }
      } catch (_) {
        // All sources unavailable or network offline
      }

      return null;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  AppReleaseInfo? _parseGitlabRelease(Map<String, dynamic> json, String currentVersion) {
    final tagName = json['tag_name'] as String? ?? '';
    final description = json['description'] as String? ?? '';
    final releasedAtStr = json['released_at'] as String?;
    final releasedAt = releasedAtStr != null ? DateTime.tryParse(releasedAtStr) : null;

    final assets = (json['assets'] as Map<String, dynamic>?)?['links'] as List<dynamic>? ?? <dynamic>[];
    String? apkUrl;

    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final url = (asset['url'] as String? ?? '');
        final directUrl = (asset['direct_asset_url'] as String? ?? '');
        if (name.endsWith('.apk') || url.endsWith('.apk') || directUrl.endsWith('.apk')) {
          apkUrl = directUrl.isNotEmpty ? directUrl : url;
          break;
        }
      }
    }

    final rawVersion = tagName.replaceFirst(RegExp(r'^[vV]'), '');
    apkUrl ??= 'https://gitlab.com/api/v4/projects/$gitlabProject/packages/generic/aperture-grafik/$rawVersion/aperture-grafik.apk';

    final remoteSemver = SemVer.parse(tagName);
    final localSemver = SemVer.parse(currentVersion);
    final isNewer = remoteSemver.isNewerThan(localSemver);

    return AppReleaseInfo(
      tag: tagName,
      version: remoteSemver.toString(),
      notes: description,
      downloadUrl: apkUrl,
      publishedAt: releasedAt,
      isNewer: isNewer,
    );
  }

  AppReleaseInfo? _parseGithubRelease(Map<String, dynamic> json, String currentVersion) {
    final tagName = json['tag_name'] as String? ?? '';
    final body = json['body'] as String? ?? '';
    final publishedAtStr = json['published_at'] as String?;
    final publishedAt = publishedAtStr != null ? DateTime.tryParse(publishedAtStr) : null;

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
      apkUrl = 'https://github.com/$githubRepo/releases/download/$tagName/aperture-grafik.apk';
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

  Stream<double> downloadApk({
    required String downloadUrl,
    required String targetPath,
    http.Client? client,
  }) async* {
    final httpClient = client ?? http.Client();
    try {
      var currentUrl = Uri.parse(downloadUrl);
      http.StreamedResponse? streamedResponse;
      var redirectCount = 0;

      while (redirectCount < 6) {
        final request = http.Request('GET', currentUrl);
        request.headers['User-Agent'] = 'ApertureGrafik-Updater';
        final response = await httpClient.send(request);

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location != null && location.isNotEmpty) {
            currentUrl = currentUrl.resolve(location);
            redirectCount++;
            continue;
          }
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('Failed to download update: HTTP ${response.statusCode}');
        }

        streamedResponse = response;
        break;
      }

      if (streamedResponse == null) {
        throw const HttpException('Too many redirects while downloading update');
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      var receivedBytes = 0;

      final file = File(targetPath);
      if (await file.exists()) {
        await file.delete();
      }
      await file.create(recursive: true);

      final sink = file.openWrite();
      try {
        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            yield receivedBytes / totalBytes;
          } else {
            yield -1.0;
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }

    yield 1.0;
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
