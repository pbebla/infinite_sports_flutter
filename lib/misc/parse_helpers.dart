/// Safe Firebase Realtime Database parsing helpers.
///
/// Firebase returns dynamic values that may not match the declared Dart type
/// (e.g. an admin edits the console and writes "true" as a string instead of
/// a bool). These helpers accept multiple input types and degrade gracefully
/// to a default rather than throwing.

bool parseBool(dynamic value, {bool defaultValue = false}) {
  if (value is bool) return value;
  if (value is int) {
    if (value == 1) return true;
    if (value == 0) return false;
  }
  if (value is String) {
    final lower = value.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
  }
  return defaultValue;
}

int parseInt(dynamic value, {int defaultValue = 0}) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  return defaultValue;
}

double parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }
  return defaultValue;
}

String parseString(dynamic value, {String defaultValue = ''}) {
  if (value == null) return defaultValue;
  if (value is String) return value;
  return value.toString();
}

Map<dynamic, dynamic> parseMap(dynamic value) {
  if (value is Map) return value;
  return <dynamic, dynamic>{};
}

/// Returns the first non-null value from a map for any of the given keys.
/// Useful for handling both CamelCase and lowercase Firebase keys.
dynamic firstNonNull(Map data, List<String> keys) {
  for (final key in keys) {
    final v = data[key];
    if (v != null) return v;
  }
  return null;
}
