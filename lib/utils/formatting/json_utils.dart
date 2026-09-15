import 'dart:convert';

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
