import 'package:aperture_grafik/domain/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final v100 = SemVer.parse('1.0.0');
      final v020b1 = SemVer.parse('0.2.0+1');
      final v020b2 = SemVer.parse('0.2.0+2');

      expect(v021.isNewerThan(v020), isTrue);
      expect(v030.isNewerThan(v021), isTrue);
      expect(v100.isNewerThan(v030), isTrue);
      expect(v020b2.isNewerThan(v020b1), isTrue);

      expect(v020.isNewerThan(v021), isFalse);
      expect(v020.isNewerThan(v020), isFalse);
    });
  });
}
