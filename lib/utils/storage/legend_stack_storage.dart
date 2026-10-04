import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/prefs_keys.dart';
import '../app_logger.dart';

List<String> _parseLegendStack(String? raw) {
  try {
    final decoded = jsonDecode(raw ?? '[]');
    if (decoded is! List) {
      log.w('Stored legend stack blob is not a list — treating as empty');
      return [];
    }
    return decoded.whereType<String>().toList();
  } catch (e) {
    // Well-formed-but-wrong-shape JSON throws TypeError, not
    // FormatException — see rp_snapshot_storage._parseSnapshots.
    log.w('Legend stack JSON parse failed — returning empty list', error: e);
    return [];
  }
}

/// Moves the legacy global stack to [uid]'s key the first time a profile asks; only the
/// first profile inherits it (the legacy key is removed).
Future<void> _adoptLegacyStack(SharedPreferences prefs, String uid) async {
  final key = PrefsKeys.legendVisitStackKeyFor(uid);
  if (prefs.containsKey(key)) return;
  final legacy = prefs.getString(PrefsKeys.legendVisitStack);
  if (legacy == null) return;
  await prefs.setString(key, legacy);
  await prefs.remove(PrefsKeys.legendVisitStack);
}

/// [uid]'s recently played legends, newest first (legacy global key without a UID).
Future<List<String>> loadLegendStack(
  SharedPreferences prefs, {
  String? uid,
}) async {
  if (uid != null && uid.isNotEmpty) await _adoptLegacyStack(prefs, uid);
  return _parseLegendStack(
    prefs.getString(PrefsKeys.legendVisitStackKeyFor(uid)),
  );
}

/// Prepends [legendName] to [uid]'s stack if it isn't already at position 0.
/// Returns the updated stack. Throws [ArgumentError] if [legendName] is empty.
Future<List<String>> pushToLegendStack(
  String legendName,
  SharedPreferences prefs, {
  String? uid,
}) async {
  if (legendName.isEmpty) throw ArgumentError('legendName must not be empty');
  if (uid != null && uid.isNotEmpty) await _adoptLegacyStack(prefs, uid);
  final key = PrefsKeys.legendVisitStackKeyFor(uid);
  final stack = _parseLegendStack(prefs.getString(key));
  if (stack.isNotEmpty && stack.first == legendName) return stack;
  stack.removeWhere((e) => e == legendName);
  stack.insert(0, legendName);
  await prefs.setString(key, jsonEncode(stack));
  return stack;
}
