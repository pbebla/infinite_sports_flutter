/// Structured match location (venue + optional address + field), parsed from
/// the per-match `Location` snapshot the Manager writes, with a fallback to
/// the legacy free-text `matchLocation` string. Pure — no Flutter imports.
class MatchLocationInfo {
  final String venue;
  final String? address;
  final String? field;

  const MatchLocationInfo({required this.venue, this.address, this.field});

  /// Builds from the match's `Location` map (preferred) or the legacy string.
  /// Returns null when there is no usable location.
  static MatchLocationInfo? fromMatch({
    required Object? location,
    required String? legacyString,
  }) {
    if (location is Map) {
      final venue = (location['Venue'] ?? location['venue'])?.toString();
      if (venue != null && venue.trim().isNotEmpty) {
        String? str(Object? v) {
          final s = v?.toString();
          return (s == null || s.trim().isEmpty) ? null : s;
        }
        return MatchLocationInfo(
          venue: venue,
          address: str(location['Address'] ?? location['address']),
          field: str(location['Field'] ?? location['field']),
        );
      }
    }
    if (legacyString != null && legacyString.trim().isNotEmpty) {
      return MatchLocationInfo(venue: legacyString);
    }
    return null;
  }

  /// Google Maps search URL — opens the OS map-app chooser. Uses the address
  /// when available, otherwise the venue name.
  String mapsUrl() {
    final query = Uri.encodeComponent((address != null && address!.trim().isNotEmpty)
        ? address!
        : venue);
    return 'https://www.google.com/maps/search/?api=1&query=$query';
  }
}
