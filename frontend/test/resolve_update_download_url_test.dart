import 'package:flutter_test/flutter_test.dart';
import 'package:pos_connect/services/version_check_service.dart';
import 'package:pos_connect/shared/widgets/app_shell.dart';

void main() {
  group('resolveUpdateDownloadUrl', () {
    const withBoth = VersionStatus(
      updateType: VersionUpdateType.optional,
      latestVersion: '2.0.0',
      latestBuild: 2,
      updateUrl: 'https://example.com/POSConnect-Client-Setup.exe',
      updateUrlAndroid: 'https://play.google.com/store/apps/details?id=x',
    );

    test('Android avec lien Android configure : utilise le lien Android', () {
      expect(
        resolveUpdateDownloadUrl(isAndroid: true, version: withBoth),
        'https://play.google.com/store/apps/details?id=x',
      );
    });

    test('Bureau : utilise toujours le lien bureau (.exe)', () {
      expect(
        resolveUpdateDownloadUrl(isAndroid: false, version: withBoth),
        'https://example.com/POSConnect-Client-Setup.exe',
      );
    });

    test('Android SANS lien Android configure : ne retombe JAMAIS sur le .exe bureau', () {
      const androidOnlyExe = VersionStatus(
        updateType: VersionUpdateType.optional,
        latestVersion: '2.0.0',
        latestBuild: 2,
        updateUrl: 'https://example.com/POSConnect-Client-Setup.exe',
        updateUrlAndroid: null,
      );
      expect(resolveUpdateDownloadUrl(isAndroid: true, version: androidOnlyExe), isNull);
    });

    test('Android avec lien Android vide : ne retombe pas non plus sur le .exe', () {
      const androidEmptyUrl = VersionStatus(
        updateType: VersionUpdateType.optional,
        latestVersion: '2.0.0',
        latestBuild: 2,
        updateUrl: 'https://example.com/POSConnect-Client-Setup.exe',
        updateUrlAndroid: '',
      );
      expect(resolveUpdateDownloadUrl(isAndroid: true, version: androidEmptyUrl), '');
    });
  });
}
