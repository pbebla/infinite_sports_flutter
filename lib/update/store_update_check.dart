// Part D (forced updates): asking the store whether this phone must update.
//
// - Android: Google Play's official in-app update check. Play only says yes
//   when this phone can really get the update (staged rollouts included).
// - iPhone: Apple's public lookup (a plain HTTPS GET that sends only the
//   app's bundle id, or its store id). The rules are in update_decision.dart.
//
// Fails open: every exception and timeout in either check means "not
// required". A forced update that cannot be obtained never locks a fan out.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:in_app_update/in_app_update.dart';
import 'package:infinite_sports_flutter/misc/app_config.dart';
import 'package:infinite_sports_flutter/update/update_decision.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// The result of one store check.
class UpdateNeed {
  const UpdateNeed({required this.required, this.storeUrl});

  /// True only on a positive, complete answer from the store.
  final bool required;

  /// Where the store said the app lives (iPhone), when it said.
  final String? storeUrl;
}

/// One platform's store check plus the action behind the `Update` button.
abstract class StoreUpdateChecker {
  const StoreUpdateChecker();

  /// Never throws in the real checkers; any failure is "not required".
  Future<UpdateNeed> check();

  /// The `Update` button.
  Future<void> startUpdate(UpdateNeed need);

  /// The `Open Google Play` button (Android only): opens the store listing.
  /// Null hides the button.
  Future<void> Function()? get openStore => null;
}

/// Platforms with no store check (anything but Android and iOS).
class NeverRequiredUpdateChecker extends StoreUpdateChecker {
  const NeverRequiredUpdateChecker();

  @override
  Future<UpdateNeed> check() async => const UpdateNeed(required: false);

  @override
  Future<void> startUpdate(UpdateNeed need) async {}
}

/// Opens [uri] in its own app (the App Store / Google Play), not in a web
/// view inside this one.
Future<bool> _openExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// The store links from `AppConfig/StoreLinks`, bounded: a slow or failed
/// read gives the built-in fallbacks instead of a wait.
Future<StoreLinks> _boundedStoreLinks(
    Future<StoreLinks> Function() storeLinks) async {
  try {
    return await storeLinks().timeout(const Duration(seconds: 5));
  } catch (_) {
    return storeLinksFrom(null);
  }
}

/// The app's App Store id (from the live listing link).
const String kIosAppStoreId = '1449327079';

/// Used when neither Apple nor `AppConfig/StoreLinks` gave a link.
const String kIosStoreFallbackUrl =
    'https://apps.apple.com/app/id$kIosAppStoreId';

/// iPhone: Apple's public lookup, then [iosUpdateRequired].
class IosStoreUpdateChecker extends StoreUpdateChecker {
  IosStoreUpdateChecker({
    Future<String?> Function(Uri uri)? fetch,
    Future<PackageInfo> Function()? packageInfo,
    String Function()? operatingSystemVersion,
    DateTime Function()? now,
    Future<StoreLinks> Function()? storeLinks,
    Future<bool> Function(Uri uri)? openUrl,
    this.limit = const Duration(seconds: 5),
  })  : _fetch = fetch,
        _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
        _osVersion =
            operatingSystemVersion ?? (() => Platform.operatingSystemVersion),
        _now = now ?? DateTime.now,
        _storeLinks = storeLinks ?? getStoreLinks,
        _openUrl = openUrl ?? _openExternally;

  final Future<String?> Function(Uri uri)? _fetch;
  final Future<PackageInfo> Function() _packageInfo;
  final String Function() _osVersion;
  final DateTime Function() _now;
  final Future<StoreLinks> Function() _storeLinks;
  final Future<bool> Function(Uri uri) _openUrl;

  /// Each lookup's time limit.
  final Duration limit;

  @override
  Future<UpdateNeed> check() async {
    try {
      final app = await _packageInfo().timeout(limit);
      var store = await _lookup({'bundleId': app.packageName});
      if (store == null) {
        // Retry once by store id (a bundle-id lookup can come back empty).
        final links = await _boundedStoreLinks(_storeLinks);
        final id = appStoreIdFrom(links.ios) ?? kIosAppStoreId;
        store = await _lookup({'id': id});
      }
      final required = iosUpdateRequired(
        installedVersion: app.version,
        deviceOsVersion: osVersionFrom(_osVersion()),
        store: store,
        now: _now(),
      );
      return UpdateNeed(required: required, storeUrl: store?.storeUrl);
    } catch (_) {
      return const UpdateNeed(required: false);
    }
  }

  /// One lookup: only the given id (and the US store) is sent. Null on no
  /// result, a bad answer, an error or the time limit.
  Future<IosStoreInfo?> _lookup(Map<String, String> id) async {
    try {
      final uri =
          Uri.https('itunes.apple.com', '/lookup', {...id, 'country': 'us'});
      final body = await (_fetch ?? _httpGet)(uri).timeout(limit);
      if (body == null) return null;
      return IosStoreInfo.fromLookupJson(body);
    } catch (_) {
      return null;
    }
  }

  /// A plain HTTPS GET with `dart:io` (no headers beyond the defaults, no
  /// user data). Null unless Apple answers 200.
  Future<String?> _httpGet(Uri uri) async {
    final client = HttpClient()..connectionTimeout = limit;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> startUpdate(UpdateNeed need) async {
    try {
      var url = need.storeUrl;
      url ??= (await _boundedStoreLinks(_storeLinks)).ios;
      url ??= kIosStoreFallbackUrl;
      await _openUrl(Uri.parse(url));
    } catch (_) {}
  }
}

/// Play's answer → required: an update is available and an immediate
/// update is allowed, or an update this app started is still in progress.
bool androidUpdateRequired(AppUpdateInfo info) =>
    (info.updateAvailability == UpdateAvailability.updateAvailable &&
        info.immediateUpdateAllowed) ||
    info.updateAvailability ==
        UpdateAvailability.developerTriggeredUpdateInProgress;

/// Android: Google Play's in-app update check and immediate update.
class AndroidStoreUpdateChecker extends StoreUpdateChecker {
  AndroidStoreUpdateChecker({
    Future<AppUpdateInfo> Function()? checkForUpdate,
    Future<AppUpdateResult> Function()? performImmediateUpdate,
    Future<StoreLinks> Function()? storeLinks,
    Future<bool> Function(Uri uri)? openUrl,
    this.limit = const Duration(seconds: 10),
  })  : _checkForUpdate = checkForUpdate ?? InAppUpdate.checkForUpdate,
        _performImmediateUpdate =
            performImmediateUpdate ?? InAppUpdate.performImmediateUpdate,
        _storeLinks = storeLinks ?? getStoreLinks,
        _openUrl = openUrl ?? _openExternally;

  final Future<AppUpdateInfo> Function() _checkForUpdate;
  final Future<AppUpdateResult> Function() _performImmediateUpdate;
  final Future<StoreLinks> Function() _storeLinks;
  final Future<bool> Function(Uri uri) _openUrl;

  /// The Play check's time limit.
  final Duration limit;

  @override
  Future<UpdateNeed> check() async {
    try {
      final info = await _checkForUpdate().timeout(limit);
      return UpdateNeed(required: androidUpdateRequired(info));
    } catch (_) {
      // Includes builds not installed from Play (Play refuses to answer).
      return const UpdateNeed(required: false);
    }
  }

  /// Asks Play again first: the immediate update needs a fresh check in
  /// this session, and a flow Play cannot start would never finish. When
  /// Play cannot run it (or it fails), the Play listing opens instead.
  @override
  Future<void> startUpdate(UpdateNeed need) async {
    try {
      final info = await _checkForUpdate().timeout(limit);
      if (!androidUpdateRequired(info)) {
        await _openPlay();
        return;
      }
      final result = await _performImmediateUpdate();
      if (result == AppUpdateResult.inAppUpdateFailed) await _openPlay();
    } catch (_) {
      await _openPlay();
    }
  }

  @override
  Future<void> Function()? get openStore => _openPlay;

  Future<void> _openPlay() async {
    try {
      final links = await _boundedStoreLinks(_storeLinks);
      await _openUrl(Uri.parse(links.android ?? kFallbackPlayUrl));
    } catch (_) {}
  }
}
