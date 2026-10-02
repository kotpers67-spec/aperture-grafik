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

    test('rejects malformed versions instead of treating them as zero', () {
      expect(() => SemVer.parse('latest'), throwsFormatException);
      expect(() => SemVer.parse('0.4'), throwsFormatException);
      expect(() => SemVer.parse('0.4.-1'), throwsFormatException);
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
    const githubJson = '''
    {
      "tag_name": "v0.3.1",
      "body": "Release v0.3.1 description",
      "published_at": "2026-09-23T17:25:13.169Z",
      "assets": [{
        "name": "aperture-grafik.apk",
        "size": 59919418,
        "browser_download_url": "https://github.com/santiyastudio-lgtm/aperture-grafik/releases/download/v0.3.1/aperture-grafik.apk"
      }]
    }
    ''';

    test(
      'detects v0.3.1 as newer from v0.2.0 and v0.3.0, but not from v0.3.1',
      () async {
        final client = MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            return http.Response(
              githubJson,
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        });

        const service = UpdateService();

        // Check from v0.2.0
        final rel020 = await service.checkForUpdates(
          currentVersion: 'v0.2.0',
          client: client,
        );
        expect(rel020, isNotNull);
        expect(rel020!.isNewer, isTrue);
        expect(rel020.tag, 'v0.3.1');
        expect(rel020.version, '0.3.1');
        expect(
          rel020.downloadUrl,
          'https://github.com/santiyastudio-lgtm/aperture-grafik/releases/download/v0.3.1/aperture-grafik.apk',
        );

        // Check from v0.3.0
        final rel030 = await service.checkForUpdates(
          currentVersion: '0.3.0',
          client: client,
        );
        expect(rel030, isNotNull);
        expect(rel030!.isNewer, isTrue);

        // Check from v0.3.1
        final rel031 = await service.checkForUpdates(
          currentVersion: '0.3.1',
          client: client,
        );
        expect(rel031, isNotNull);
        expect(rel031!.isNewer, isFalse);

        // Check from v0.3.1+4
        final rel031b4 = await service.checkForUpdates(
          currentVersion: '0.3.1+4',
          client: client,
        );
        expect(rel031b4, isNotNull);
        expect(rel031b4!.isNewer, isFalse);
      },
    );

    test('uses GitHub Releases as the only update source', () async {
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

      final requestedHosts = <String>[];
      final client = MockClient((request) async {
        requestedHosts.add(request.url.host);
        if (request.url.host == 'api.github.com') {
          return http.Response(
            githubJson,
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      const service = UpdateService();
      final release = await service.checkForUpdates(
        currentVersion: '0.3.0',
        client: client,
      );

      expect(release, isNotNull);
      expect(release!.isNewer, isTrue);
      expect(release.tag, 'v0.3.1');
      expect(release.sizeBytes, 59919418);
      expect(
        release.downloadUrl,
        'https://github.com/santiyastudio-lgtm/aperture-grafik/releases/download/v0.3.1/aperture-grafik.apk',
      );
      expect(requestedHosts, ['api.github.com']);
    });
  });

  group('UpdateService downloadApk streaming & errors', () {
    test('refuses insecure download URLs before making a request', () async {
      var requested = false;
      final client = MockClient((request) async {
        requested = true;
        return http.Response('', 200);
      });

      const service = UpdateService();
      await expectLater(
        service
            .downloadApk(
              downloadUrl: 'http://example.com/update.apk',
              targetPath: '${Directory.systemTemp.path}/insecure.apk',
              client: client,
            )
            .toList(),
        throwsA(isA<HttpException>()),
      );
      expect(requested, isFalse);
    });

    test(
      'rejects an incomplete response and removes the partial file',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'update_partial_',
        );
        final targetFile = File('${tempDir.path}/partial.apk');
        final client = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream.value(Uint8List.fromList([1, 2, 3])),
            200,
            contentLength: 4,
          );
        });

        const service = UpdateService();
        await expectLater(
          service
              .downloadApk(
                downloadUrl: 'https://example.com/update.apk',
                targetPath: targetFile.path,
                client: client,
              )
              .toList(),
          throwsA(isA<HttpException>()),
        );
        expect(await targetFile.exists(), isFalse);
        await tempDir.delete(recursive: true);
      },
    );

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
      final progressList = await service
          .downloadApk(
            downloadUrl: 'https://example.com/test.apk',
            targetPath: targetFile.path,
            client: streamingClient,
          )
          .toList();

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
        () => service
            .downloadApk(
              downloadUrl: 'https://example.com/nonexistent.apk',
              targetPath: targetFile.path,
              client: errorClient,
            )
            .toList(),
        throwsA(isA<HttpException>()),
      );

      await tempDir.delete(recursive: true);
    });
  });
}
