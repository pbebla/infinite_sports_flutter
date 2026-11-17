// Part D (forced updates): the pure rules behind "Update required".
//
// Fails open everywhere: an unreadable version, a missing date, an unknown
// phone OS version or a malformed store answer all come out "not required".
// Only a positive, complete answer from the store blocks a fan.

import 'dart:convert';
import 'dart:math' as math;

/// The dotted numbers of a version (`5.1.0+30` → [5, 1, 0]); a `+build`
/// suffix is ignored. Null when any part is not a whole number.
List<int>? _versionParts(String version) {
  final core = version.split('+').first.trim();
  if (core.isEmpty) return null;
  final parts = <int>[];
  for (final piece in core.split('.')) {
    final n = int.tryParse(piece.trim());
    if (n == null || n < 0) return null;
    parts.add(n);
  }
  return parts;
}

/// True when [store] is a higher version than [installed], compared as
/// numbers part by part (`5.10.0` is newer than `5.9.9`; `5.1` equals
/// `5.1.0`; a `+build` suffix is ignored). Anything unparseable is false.
bool isNewerVersion(String store, String installed) {
  final a = _versionParts(store);
  final b = _versionParts(installed);
  if (a == null || b == null) return false;
  final length = math.max(a.length, b.length);
  for (var i = 0; i < length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// What Apple's public lookup says about the app's current store release.
class IosStoreInfo {
  const IosStoreInfo({
    required this.version,
    this.releasedAt,
    this.minimumOsVersion,
    this.storeUrl,
  });

  final String version;
  final DateTime? releasedAt;
  final String? minimumOsVersion;
  final String? storeUrl;

  /// Reads `results[0]` of an `itunes.apple.com/lookup` body (`version`,
  /// `currentVersionReleaseDate`, `minimumOsVersion`, `trackViewUrl`). Null
  /// when there is no result, no version, or the JSON is malformed.
  static IosStoreInfo? fromLookupJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final results = decoded['results'];
      if (results is! List || results.isEmpty) return null;
      final first = results.first;
      if (first is! Map) return null;
      final version = _text(first['version']);
      if (version == null) return null;
      final released = _text(first['currentVersionReleaseDate']);
      return IosStoreInfo(
        version: version,
        releasedAt: released == null ? null : DateTime.tryParse(released),
        minimumOsVersion: _text(first['minimumOsVersion']),
        storeUrl: _text(first['trackViewUrl']),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Apple can take up to a day to offer a new release in every country, so
/// an iPhone is only told to update once the release is this old.
const Duration kIosUpdateGrace = Duration(hours: 24);

/// True only when every one of these holds: Apple answered ([store] not
/// null); its version is newer than [installedVersion]; it was released at
/// least [kIosUpdateGrace] before [now]; and it runs on this phone (no
/// minimum iOS, or [deviceOsVersion] is readable and not lower than it).
bool iosUpdateRequired({
  required String installedVersion,
  required String? deviceOsVersion,
  required IosStoreInfo? store,
  required DateTime now,
}) {
  if (store == null) return false;
  if (!isNewerVersion(store.version, installedVersion)) return false;
  final releasedAt = store.releasedAt;
  if (releasedAt == null) return false;
  if (now.difference(releasedAt) < kIosUpdateGrace) return false;
  final minimumOs = store.minimumOsVersion;
  if (minimumOs != null) {
    if (deviceOsVersion == null) return false;
    if (_versionParts(minimumOs) == null) return false;
    if (_versionParts(deviceOsVersion) == null) return false;
    if (isNewerVersion(minimumOs, deviceOsVersion)) return false;
  }
  return true;
}

/// The first dotted number in `Platform.operatingSystemVersion` (iOS gives
/// `Version 17.5 (Build 21F79)` → `17.5`); null when there is none.
String? osVersionFrom(String platformVersionString) =>
    RegExp(r'\d+(?:\.\d+)+').firstMatch(platformVersionString)?.group(0);

/// The App Store id in a store link: the digits after `/id`
/// (`…/infinite-sports/id1449327079` → `1449327079`); null when absent.
String? appStoreIdFrom(String? storeLink) {
  if (storeLink == null) return null;
  return RegExp(r'/id(\d+)').firstMatch(storeLink)?.group(1);
}

/// The Manager's pause switch, `AppConfig/ForceUpdate`: true only when the
/// node is a map whose `PausedUntil` (epoch ms) is a number after [nowMs].
/// Absent, past or unreadable means forced updates are on.
bool forceUpdatePaused(Object? forceUpdateNode, int nowMs) {
  if (forceUpdateNode is! Map) return false;
  final until = forceUpdateNode['PausedUntil'];
  return until is num && until > nowMs;
}
