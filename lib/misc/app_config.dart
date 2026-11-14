import 'package:flutter/foundation.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';

/// App store listing URLs, owner-configurable at `AppConfig/StoreLinks`
/// in the manager so a listing change never needs an app release.
class StoreLinks {
  const StoreLinks({this.android, this.ios});

  final String? android;
  final String? ios;
}

/// Derivable from the package id — used when the config node is absent.
const String kFallbackPlayUrl =
    'https://play.google.com/store/apps/details?id=com.infinitesports.Infinite_Sports_App';

StoreLinks? _cached;

/// Fresh reads (Task 4, survey list B): a newer `AppConfig/StoreLinks` from
/// the server refills [_cached]. App lifetime; started by the first read.
VoidCallback? _cacheFollow;

/// The links in an `AppConfig/StoreLinks` value (Play URL fallback).
StoreLinks storeLinksFrom(Object? value) {
  String? android;
  String? ios;
  if (value is Map) {
    final a = value['Android']?.toString().trim() ?? '';
    final i = value['iOS']?.toString().trim() ?? '';
    if (a.isNotEmpty) android = a;
    if (i.isNotEmpty) ios = i;
  }
  return StoreLinks(android: android ?? kFallbackPlayUrl, ios: ios);
}

/// One read per session (refilled when the server has newer links); falls
/// back to the Play URL so shares always carry at least one download link.
Future<StoreLinks> getStoreLinks() async {
  _cacheFollow ??= FreshReads.onNewer(
      'AppConfig/StoreLinks', (v) => _cached = storeLinksFrom(v));
  final cached = _cached;
  if (cached != null) return cached;
  Object? value;
  try {
    value = await refreshingValue('AppConfig/StoreLinks');
  } catch (_) {}
  final links = storeLinksFrom(value);
  _cached = links;
  return links;
}

/// Test seam: forgets the cache and its follower.
@visibleForTesting
void debugResetStoreLinks() {
  _cacheFollow?.call();
  _cacheFollow = null;
  _cached = null;
}
