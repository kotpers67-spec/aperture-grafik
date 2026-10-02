import 'dart:io';
import 'dart:typed_data';

import 'package:aperture_grafik/domain/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('SemVer parser & comparison', () {
    test('parses basic semver', () {
      final v1 = SemVer.parse('1.2.3');
      expect(v1.major, 1);
      expect(v1.minor, 2);
      expect(v1.patch, 3);
      expect(v1.build, 0);
    });

    test('parses version with v prefix and build number', () {
      final v = SemVer.parse('v0.2.1+5');
      expect(v.major, 0);
      expect(v.minor, 2);
      expect(v.patch, 1);
      expect(v.build, 5);
    });

    test('correctly identifies newer versions', () {
      final v020 = SemVer.parse('0.2.0');
      final v021 = SemVer.parse('0.2.1');
      final v030 = SemVer.parse('0.3.0');
      final v031 = SemVer.parse('0.3.1');
      final v031b4 = SemVer.parse('0.3.1+4');
      final v100 = SemVer.parse('1.0.0');
      final v020b1 = SemVer.parse('0.2.0+1');
      final v020b2 = SemVer.parse('0.2.0+2');

      expect(v021.isNewerThan(v020), isTrue);
      expect(v030.isNewerThan(v021), isTrue);
      expect(v031.isNewerThan(v020), isTrue);
      expect(v031.isNewerThan(v030), isTrue);
      expect(v031b4.isNewerThan(v031), isTrue);
      expect(v100.isNewerThan(v030), isTrue);
      expect(v020b2.isNewerThan(v020b1), isTrue);

      expect(v020.isNewerThan(v021), isFalse);
      expect(v020.isNewerThan(v031), isFalse);
      expect(v030.isNewerThan(v031), isFalse);
      expect(v031.isNewerThan(v031), isFalse);
      expect(v031.isNewerThan(v031b4), isFalse);
    });
  });

  group('DownloadProgress & AppReleaseInfo formatting', () {
    test('displaySize formats bytes to megabytes', () {
      const info = AppReleaseInfo(
        tag: 'v0.3.1',
        version: '0.3.1',
        notes: '',
        downloadUrl: '',
        sizeBytes: 59919418,
      );
      expect(info.displaySize, '57.1 МБ');

      const infoZero = AppReleaseInfo(
        tag: 'v0.3.1',
        version: '0.3.1',
        notes: '',
        downloadUrl: '',
        sizeBytes: 0,
      );
      expect(infoZero.displaySize, '');
    });

    test('etaString formats remaining seconds correctly in RU and EN', () {
      const p1 = DownloadProgress(
        fraction: 0.5,
        receivedBytes: 500,
        totalBytes: 1000,
        remainingSeconds: 45,
      );
      expect(p1.etaString(true), '45 сек');
      expect(p1.etaString(false), '45 sec');

      const p2 = DownloadProgress(
        fraction: 0.5,
        receivedBytes: 500,
        totalBytes: 1000,
        remainingSeconds: 125,
      );
      expect(p2.etaString(true), '3 мин');
      expect(p2.etaString(false), '3 min');

      const p3 = DownloadProgress(
        fraction: 0.5,
        receivedBytes: 500,
        totalBytes: 1000,
        remainingSeconds: 0,
      );
      expect(p3.etaString(true), '');
    });
  });

  group('UpdateService checkForUpdates', () {
    const gitlabJson = '''
    {
      "tag_name": "v0.3.1",
      "name": "v0.3.1 - In-App Background Updater & Telegram Feedback",
      "description": "Release v0.3.1 description",
      "released_at": "2026-09-23T17:25:13.169Z",
      "assets": {
        "count": 1,
        "links": [
          {
            "id": 1,
            "name": "aperture-grafik.apk",
            "url": "https://gitlab.com/api/v4/projects/santiyastudio%2Faperture-grafik/packages/generic/aperture-grafik/0.3.1/aperture-grafik.apk",
            "direct_asset_url": "https://gitlab.com/api/v4/projects/santiyastudio%2Faperture-grafik/packages/generic/aperture-grafik/0.3.1/aperture-grafik.apk",
            "link_type": "package"
          }
        ]
      }
    }
    ''';

    test('detects v0.3.1 as newer from v0.2.0 and v0.3.0, but not from v0.3.1', () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('releases/permalink/latest')) {
          return http.Response(gitlabJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      const service = UpdateService();

      // Check from v0.2.0
      final rel020 = await service.checkForUpdates(currentVersion: 'v0.2.0', client: client);
      expect(rel020, isNotNull);
      expect(rel020!.isNewer, isTrue);
      expect(rel020.tag, 'v0.3.1');
      expect(rel020.version, '0.3.1');
      expect(
        rel020.downloadUrl,
        'https://gitlab.com/api/v4/projects/santiyastudio%2Faperture-grafik/packages/generic/aperture-grafik/0.3.1/aperture-grafik.apk',
      );

      // Check from v0.3.0
      final rel030 = await service.checkForUpdates(currentVersion: '0.3.0', client: client);
      expect(rel030, isNotNull);
      expect(rel030!.isNewer, isTrue);

      // Check from v0.3.1
      final rel031 = await service.checkForUpdates(currentVersion: '0.3.1', client: client);
      expect(rel031, isNotNull);
      expect(rel031!.isNewer, isFalse);

      // Check from v0.3.1+4
      final rel031b4 = await service.checkForUpdates(currentVersion: '0.3.1+4', client: client);
      expect(rel031b4, isNotNull);
      expect(rel031b4!.isNewer, isFalse);
    });

    test('falls back to secondary GitHub endpoint if GitLab is unreachable', () async {
      const githubJson = '''
      {
        "tag_name": "v0.3.1",
        "body": "GitHub release notes",
        "published_at": "2026-09-23T17:26:27Z",
        "assets": [
          {
            "name": "aperture-grafik.apk",
            "size": 59919418,
            "browser_download_url": "https://github.com/santiyastudio-lgtm/aperture-grafik/releases/download/v0.3.1/aperture-grafik.apk"
          }
        ]
      }
      ''';

      final client = MockClient((request) async {
        if (request.url.host == 'gitlab.com') {
          return http.Response('Server Error', 500);
        }
        if (request.url.host == 'api.github.com') {
          return http.Response(githubJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      const service = UpdateService();
      final release = await service.checkForUpdates(currentVersion: '0.3.0', client: client);

      expect(release, isNotNull);
      expect(release!.isNewer, isTrue);
      expect(release.tag, 'v0.3.1');
      expect(release.sizeBytes, 59919418);
      expect(release.downloadUrl, 'https://github.com/santiyastudio-lgtm/aperture-grafik/releases/download/v0.3.1/aperture-grafik.apk');
    });
  });

  group('UpdateService downloadApk streaming & errors', () {
    test('streams download chunks and writes file to targetPath', () async {
      final tempDir = await Directory.systemTemp.createTemp('update_test_');
      final targetFile = File('${tempDir.path}/test_download.apk');
      final chunk = Uint8List.fromList(List.generate(2048, (i) => i % 256));

      final streamingClient = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable([chunk, chunk]),
          200,
          contentLength: 4096,
          headers: {'content-type': 'application/vnd.android.package-archive'},
        );
      });

      const service = UpdateService();
      final progressList = await service.downloadApk(
        downloadUrl: 'https://example.com/test.apk',
        targetPath: targetFile.path,
        client: streamingClient,
      ).toList();

      expect(progressList.length, greaterThanOrEqualTo(2));
      expect(await targetFile.exists(), isTrue);
      expect(await targetFile.length(), 4096);

      await tempDir.delete(recursive: true);
    });

    test('throws HttpException when status code is 404', () async {
      final tempDir = await Directory.systemTemp.createTemp('update_test_err_');
      final targetFile = File('${tempDir.path}/error.apk');

      final errorClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      const service = UpdateService();
      expect(
        () => service.downloadApk(
          downloadUrl: 'https://example.com/nonexistent.apk',
          targetPath: targetFile.path,
          client: errorClient,
        ).toList(),
        throwsA(isA<HttpException>()),
      );

      await tempDir.delete(recursive: true);
    });
  });

  group('Live network validation (GitLab endpoint)', () {
    test('queries live GitLab release permalink and detects updates dynamically', () async {
      const service = UpdateService();

      // Check from v0.2.0
      final rel020 = await service.checkForUpdates(currentVersion: '0.2.0');
      expect(rel020, isNotNull);
      expect(rel020!.tag, startsWith('v'));
      expect(rel020.isNewer, isTrue);
      expect(
        rel020.downloadUrl,
        endsWith('/${rel020.version}/aperture-grafik.apk'),
      );
      final current = await service.checkForUpdates(
        currentVersion: rel020.version,
      );
      expect(current, isNotNull);
      expect(current!.isNewer, isFalse);
    });
  });
}
