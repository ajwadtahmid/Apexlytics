import 'dart:convert';

/// [v] as a JSON object, or null for anything else. A PHP-backed API sends an
/// empty object as `[]`, which must read as absent, not throw.
Map<String, dynamic>? asObject(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : null;

/// [v] as a JSON array, or null for anything else.
List<dynamic>? asList(Object? v) => v is List ? v : null;

/// [v] as a string, or null for anything else.
String? asString(Object? v) => v is String ? v : null;

/// Decodes a JSON-encoded string array from SharedPreferences.
/// Returns an empty list on null input, malformed JSON, or JSON whose shape
/// isn't a list — the last of those throws TypeError on the `as List?` cast
/// rather than FormatException, so the catch is deliberately broad. See
/// rp_snapshot_storage._parseSnapshots for the same reasoning.
List<String> parseStringList(String? raw) {
  try {
    final list = (raw != null ? jsonDecode(raw) as List? : null) ?? [];
    return list.whereType<String>().toList();
  } catch (e) {
    return [];
  }
}
