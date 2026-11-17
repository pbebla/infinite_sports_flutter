// Part D (forced updates): the pure rules behind "Update required".
// Every unknown or unreadable case must come out "not required" (fails open).

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/update/update_decision.dart';

/// A real-shaped body from Apple's public lookup (trimmed to the fields the
/// app reads plus a few neighbours).
const String _lookupBody = '''
{
 "resultCount":1,
 "results": [
  {"kind":"software", "trackId":1449327079,
   "bundleId":"com.infinitesports.Infinite-Sports",
   "trackViewUrl":"https://apps.apple.com/us/app/infinite-sports/id1449327079?uo=4",
   "version":"5.1.0",
   "currentVersionReleaseDate":"2026-11-10T18:04:33Z",
   "minimumOsVersion":"14.0",
   "releaseNotes":"Bug fixes."}]
}
''';

void main() {
  group('isNewerVersion', () {
    test('5.1.0 is newer than 5.0.0', () {
      expect(isNewerVersion('5.1.0', '5.0.0'), isTrue);
    });
    test('5.10.0 is newer than 5.9.9 (numbers, not text)', () {
      expect(isNewerVersion('5.10.0', '5.9.9'), isTrue);
    });
    test('5.1 equals 5.1.0', () {
      expect(isNewerVersion('5.1', '5.1.0'), isFalse);
      expect(isNewerVersion('5.1.0', '5.1'), isFalse);
    });
    test('a +build suffix is ignored', () {
      expect(isNewerVersion('5.0.0', '5.0.0+30'), isFalse);
      expect(isNewerVersion('5.0.0+31', '5.0.0+30'), isFalse);
    });
    test('older store version is not newer', () {
      expect(isNewerVersion('4.9.0', '5.0.0'), isFalse);
    });
    test('anything unparseable is false', () {
      expect(isNewerVersion('abc', '5.0.0'), isFalse);
      expect(isNewerVersion('5.0.0', 'abc'), isFalse);
      expect(isNewerVersion('', '5.0.0'), isFalse);
      expect(isNewerVersion('6.x', '5.0.0'), isFalse);
    });
  });

  group('IosStoreInfo.fromLookupJson', () {
    test('a real-shaped body parses', () {
      final info = IosStoreInfo.fromLookupJson(_lookupBody);
      expect(info, isNotNull);
      expect(info!.version, '5.1.0');
      expect(info.releasedAt, DateTime.utc(2026, 11, 10, 18, 4, 33));
      expect(info.minimumOsVersion, '14.0');
      expect(info.storeUrl,
          'https://apps.apple.com/us/app/infinite-sports/id1449327079?uo=4');
    });
    test('resultCount 0 is null', () {
      expect(IosStoreInfo.fromLookupJson('{"resultCount":0,"results":[]}'),
          isNull);
    });
    test('malformed is null', () {
      expect(IosStoreInfo.fromLookupJson('not json {'), isNull);
      expect(IosStoreInfo.fromLookupJson(''), isNull);
      expect(IosStoreInfo.fromLookupJson('[]'), isNull);
      expect(
          IosStoreInfo.fromLookupJson('{"results":[{"version":7}]}'), isNull);
    });
    test('missing optional fields stay null', () {
      final info =
          IosStoreInfo.fromLookupJson('{"results":[{"version":"5.1.0"}]}');
      expect(info, isNotNull);
      expect(info!.releasedAt, isNull);
      expect(info.minimumOsVersion, isNull);
      expect(info.storeUrl, isNull);
    });
  });

  group('iosUpdateRequired (Review Focus 6)', () {
    final now = DateTime.utc(2026, 11, 16, 12);
    IosStoreInfo store({
      String version = '5.1.0',
      Duration? releasedAgo = const Duration(hours: 25),
      String? minimumOs = '14.0',
    }) =>
        IosStoreInfo(
          version: version,
          releasedAt: releasedAgo == null ? null : now.subtract(releasedAgo),
          minimumOsVersion: minimumOs,
          storeUrl: 'https://apps.apple.com/app/id1449327079',
        );

    bool required(IosStoreInfo? s,
            {String installed = '5.0.0', String? os = '17.5'}) =>
        iosUpdateRequired(
            installedVersion: installed,
            deviceOsVersion: os,
            store: s,
            now: now);

    test('newer and released 25 h ago: required', () {
      expect(required(store()), isTrue);
    });
    test('released exactly 24 h ago: required', () {
      expect(required(store(releasedAgo: kIosUpdateGrace)), isTrue);
    });
    test('newer but released 2 h ago: not required', () {
      expect(required(store(releasedAgo: const Duration(hours: 2))), isFalse);
    });
    test('same version: not required', () {
      expect(required(store(version: '5.0.0')), isFalse);
    });
    test('store older than installed: not required', () {
      expect(required(store(version: '4.9.0')), isFalse);
    });
    test('minimum iOS above the phone\'s: not required', () {
      expect(required(store(minimumOs: '18.0'), os: '17.5'), isFalse);
    });
    test(
        'minimum iOS present but the phone\'s version unreadable: '
        'not required', () {
      expect(required(store(minimumOs: '14.0'), os: null), isFalse);
      expect(required(store(minimumOs: '14.0'), os: 'unknown'), isFalse);
    });
    test('minimum iOS unreadable: not required', () {
      expect(required(store(minimumOs: 'soon')), isFalse);
    });
    test('no minimum iOS and the phone\'s version unknown: required', () {
      expect(required(store(minimumOs: null), os: null), isTrue);
    });
    test('no release date: not required', () {
      expect(required(store(releasedAgo: null)), isFalse);
    });
    test('null store: not required', () {
      expect(required(null), isFalse);
    });
  });

  group('osVersionFrom', () {
    test('reads the first dotted number', () {
      expect(osVersionFrom('Version 17.5 (Build 21F79)'), '17.5');
      expect(osVersionFrom('Version 17.5.1 (Build 21F90)'), '17.5.1');
    });
    test('null when there is none', () {
      expect(osVersionFrom(''), isNull);
      expect(osVersionFrom('Version unknown'), isNull);
    });
  });

  group('appStoreIdFrom', () {
    test('the digits after /id in a store link', () {
      expect(
          appStoreIdFrom(
              'https://apps.apple.com/us/app/infinite-sports/id1449327079'),
          '1449327079');
      expect(appStoreIdFrom('https://apps.apple.com/app/id123?uo=4'), '123');
    });
    test('null when there are none', () {
      expect(appStoreIdFrom(null), isNull);
      expect(appStoreIdFrom('https://apps.apple.com/us/app/x'), isNull);
    });
  });

  group('forceUpdatePaused', () {
    const nowMs = 1763300000000;
    test('a future PausedUntil: paused', () {
      expect(forceUpdatePaused({'PausedUntil': nowMs + 1000}, nowMs), isTrue);
    });
    test('a past PausedUntil: not paused', () {
      expect(forceUpdatePaused({'PausedUntil': nowMs - 1000}, nowMs), isFalse);
    });
    test('absent: not paused', () {
      expect(forceUpdatePaused(null, nowMs), isFalse);
      expect(forceUpdatePaused(<String, Object?>{}, nowMs), isFalse);
    });
    test('not a number: not paused', () {
      expect(forceUpdatePaused({'PausedUntil': 'tomorrow'}, nowMs), isFalse);
      expect(forceUpdatePaused({'PausedUntil': '${nowMs + 1000}'}, nowMs),
          isFalse);
      expect(forceUpdatePaused('PausedUntil', nowMs), isFalse);
    });
  });
}
