// Part D (forced updates): the two store checks, with every platform and
// network call swapped for a fake. Only a positive, complete store answer
// blocks; any error or timeout lets the fan in.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:infinite_sports_flutter/misc/app_config.dart';
import 'package:infinite_sports_flutter/update/store_update_check.dart';
import 'package:package_info_plus/package_info_plus.dart';

final _now = DateTime.utc(2026, 11, 16, 12);

String _lookup(
        {String version = '5.1.0', Duration ago = const Duration(hours: 25)}) =>
    '{"resultCount":1,"results":[{"version":"$version",'
    '"currentVersionReleaseDate":"${_now.subtract(ago).toIso8601String()}",'
    '"minimumOsVersion":"14.0",'
    '"trackViewUrl":"https://apps.apple.com/us/app/infinite-sports/id1449327079?uo=4"}]}';

const _empty = '{"resultCount":0,"results":[]}';

PackageInfo _app({String version = '5.0.0'}) => PackageInfo(
      appName: 'Infinite Sports',
      packageName: 'com.example.sports',
      version: version,
      buildNumber: '30',
    );

AppUpdateInfo _play(UpdateAvailability availability,
        {bool immediateAllowed = true}) =>
    AppUpdateInfo(
      updateAvailability: availability,
      immediateUpdateAllowed: immediateAllowed,
      immediateAllowedPreconditions: const [],
      flexibleUpdateAllowed: true,
      flexibleAllowedPreconditions: const [],
      availableVersionCode: 31,
      installStatus: InstallStatus.unknown,
      packageName: 'com.example.sports',
      clientVersionStalenessDays: null,
      updatePriority: 0,
    );

void main() {
  group('IosStoreUpdateChecker', () {
    late List<Uri> fetched;
    late List<Uri> opened;

    IosStoreUpdateChecker ios(
      List<String? Function()> answers, {
      String? storeLinkIos =
          'https://apps.apple.com/us/app/infinite-sports/id1449327079',
      Duration limit = const Duration(seconds: 5),
    }) {
      var call = 0;
      return IosStoreUpdateChecker(
        fetch: (uri) async {
          fetched.add(uri);
          return answers[call++]();
        },
        packageInfo: () async => _app(),
        operatingSystemVersion: () => 'Version 17.5 (Build 21F79)',
        now: () => _now,
        storeLinks: () async => StoreLinks(ios: storeLinkIos),
        openUrl: (uri) async {
          opened.add(uri);
          return true;
        },
        limit: limit,
      );
    }

    setUp(() {
      fetched = [];
      opened = [];
    });

    test(
        'a newer store version released 25 h ago: required, with the '
        'store url; only the bundle id is sent', () async {
      final need = await ios([() => _lookup()]).check();

      expect(need.required, isTrue);
      expect(need.storeUrl,
          'https://apps.apple.com/us/app/infinite-sports/id1449327079?uo=4');
      expect(fetched, hasLength(1));
      expect(fetched.single.host, 'itunes.apple.com');
      expect(fetched.single.path, '/lookup');
      expect(fetched.single.queryParameters,
          {'bundleId': 'com.example.sports', 'country': 'us'});
    });

    test('released 2 h ago: not required', () async {
      final need =
          await ios([() => _lookup(ago: const Duration(hours: 2))]).check();
      expect(need.required, isFalse);
    });

    test('no result for the bundle id: retries once with the store id',
        () async {
      final need = await ios([() => _empty, () => _lookup()]).check();

      expect(need.required, isTrue);
      expect(fetched, hasLength(2));
      expect(fetched[1].queryParameters, {'id': '1449327079', 'country': 'us'});
    });

    test('no result either way: not required, two lookups only', () async {
      final need = await ios([() => _empty, () => _empty]).check();
      expect(need.required, isFalse);
      expect(fetched, hasLength(2));
    });

    test('the lookup throws: not required', () async {
      final need = await ios([() => throw const SocketExceptionLike()]).check();
      expect(need.required, isFalse);
    });

    test('the lookup hangs: not required after the limit', () async {
      final hang = Completer<String?>();
      final checker = IosStoreUpdateChecker(
        fetch: (_) => hang.future,
        packageInfo: () async => _app(),
        operatingSystemVersion: () => 'Version 17.5 (Build 21F79)',
        now: () => _now,
        storeLinks: () async => const StoreLinks(),
        openUrl: (_) async => true,
        limit: const Duration(milliseconds: 20),
      );
      final need = await checker.check();
      expect(need.required, isFalse);
    });

    test('Update opens the store url from the check', () async {
      await ios([]).startUpdate(const UpdateNeed(
          required: true, storeUrl: 'https://apps.apple.com/app/id1'));
      expect(opened.single.toString(), 'https://apps.apple.com/app/id1');
    });

    test(
        'Update without a store url opens StoreLinks.ios, else the fixed '
        'listing', () async {
      await ios([]).startUpdate(const UpdateNeed(required: true));
      expect(opened.single.toString(),
          'https://apps.apple.com/us/app/infinite-sports/id1449327079');

      opened.clear();
      await ios([], storeLinkIos: null)
          .startUpdate(const UpdateNeed(required: true));
      expect(opened.single.toString(), kIosStoreFallbackUrl);
    });

    test('there is no Open Google Play button on iPhone', () {
      expect(ios([]).openStore, isNull);
    });
  });

  group('AndroidStoreUpdateChecker', () {
    late List<Uri> opened;
    setUp(() => opened = []);

    AndroidStoreUpdateChecker android({
      Future<AppUpdateInfo> Function()? check,
      Future<AppUpdateResult> Function()? perform,
      String? playLink = 'https://play.example.test/details?id=x',
    }) =>
        AndroidStoreUpdateChecker(
          checkForUpdate:
              check ?? () async => _play(UpdateAvailability.updateAvailable),
          performImmediateUpdate:
              perform ?? () async => AppUpdateResult.success,
          storeLinks: () async => StoreLinks(android: playLink),
          openUrl: (uri) async {
            opened.add(uri);
            return true;
          },
        );

    test('update available and an immediate update allowed: required',
        () async {
      final need = await android(
          check: () async => _play(UpdateAvailability.updateAvailable)).check();
      expect(need.required, isTrue);
    });

    test(
        'update available but an immediate update not allowed: '
        'not required', () async {
      final need = await android(
          check: () async => _play(UpdateAvailability.updateAvailable,
              immediateAllowed: false)).check();
      expect(need.required, isFalse);
    });

    test('an update this app started is in progress: required', () async {
      final need = await android(
          check: () async => _play(
              UpdateAvailability.developerTriggeredUpdateInProgress,
              immediateAllowed: false)).check();
      expect(need.required, isTrue);
    });

    test('no update or unknown: not required', () async {
      expect(
          (await android(
                  check: () async =>
                      _play(UpdateAvailability.updateNotAvailable)).check())
              .required,
          isFalse);
      expect(
          (await android(check: () async => _play(UpdateAvailability.unknown))
                  .check())
              .required,
          isFalse);
    });

    test('Play check throws (e.g. a sideloaded build): not required', () async {
      final need = await android(
              check: () async => throw PlatformException(code: 'TASK_FAILURE'))
          .check();
      expect(need.required, isFalse);
    });

    test('Update runs the immediate update; nothing else opens', () async {
      var performed = 0;
      await android(perform: () async {
        performed++;
        return AppUpdateResult.success;
      }).startUpdate(const UpdateNeed(required: true));
      expect(performed, 1);
      expect(opened, isEmpty);
    });

    test('the immediate update throws: Google Play opens', () async {
      await android(
              perform: () async =>
                  throw PlatformException(code: 'REQUIRE_FOREGROUND_ACTIVITY'))
          .startUpdate(const UpdateNeed(required: true));
      expect(
          opened.single.toString(), 'https://play.example.test/details?id=x');
    });

    test('the immediate update fails: Google Play opens', () async {
      await android(perform: () async => AppUpdateResult.inAppUpdateFailed)
          .startUpdate(const UpdateNeed(required: true));
      expect(
          opened.single.toString(), 'https://play.example.test/details?id=x');
    });

    test(
        'Play no longer offers the update at tap time: Google Play opens '
        'and the immediate update is not tried (it could never finish)',
        () async {
      var performed = 0;
      await android(
        check: () async => _play(UpdateAvailability.updateNotAvailable),
        perform: () async {
          performed++;
          return AppUpdateResult.success;
        },
      ).startUpdate(const UpdateNeed(required: true));
      expect(performed, 0);
      expect(
          opened.single.toString(), 'https://play.example.test/details?id=x');
    });

    test(
        'the Play check fails at tap time: Google Play opens and the '
        'immediate update is not tried', () async {
      var performed = 0;
      await android(
        check: () async => throw PlatformException(code: 'TASK_FAILURE'),
        perform: () async {
          performed++;
          return AppUpdateResult.success;
        },
      ).startUpdate(const UpdateNeed(required: true));
      expect(performed, 0);
      expect(
          opened.single.toString(), 'https://play.example.test/details?id=x');
    });

    test('the fan cancels the update: nothing else opens', () async {
      await android(perform: () async => AppUpdateResult.userDeniedUpdate)
          .startUpdate(const UpdateNeed(required: true));
      expect(opened, isEmpty);
    });

    test('Open Google Play opens the listing, else the fixed Play url',
        () async {
      await android().openStore!();
      expect(
          opened.single.toString(), 'https://play.example.test/details?id=x');

      opened.clear();
      await android(playLink: null).openStore!();
      expect(opened.single.toString(), kFallbackPlayUrl);
    });
  });

  test('a checker that never requires an update', () async {
    expect(
        (await const NeverRequiredUpdateChecker().check()).required, isFalse);
  });
}

class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
