import 'package:firebase_database/firebase_database.dart';

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

/// One read per session; falls back to the Play URL so shares always carry
/// at least one download link.
Future<StoreLinks> getStoreLinks() async {
  final cached = _cached;
  if (cached != null) return cached;
  String? android;
  String? ios;
  try {
    final snap = await FirebaseDatabase.instance.ref('AppConfig/StoreLinks').get();
    if (snap.value is Map) {
      final map = snap.value as Map;
      final a = map['Android']?.toString().trim() ?? '';
      final i = map['iOS']?.toString().trim() ?? '';
      if (a.isNotEmpty) android = a;
      if (i.isNotEmpty) ios = i;
    }
  } catch (_) {}
  final links = StoreLinks(android: android ?? kFallbackPlayUrl, ios: ios);
  _cached = links;
  return links;
}
