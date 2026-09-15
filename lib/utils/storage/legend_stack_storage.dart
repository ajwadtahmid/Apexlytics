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

Future<List<String>> loadLegendStack(SharedPreferences prefs) async {
  return _parseLegendStack(prefs.getString(PrefsKeys.legendVisitStack));
}

/// Prepends [legendName] to the stack if it isn't already at position 0.
/// Returns the updated stack. Throws [ArgumentError] if [legendName] is empty.
Future<List<String>> pushToLegendStack(
  String legendName,
  SharedPreferences prefs,
) async {
  if (legendName.isEmpty) throw ArgumentError('legendName must not be empty');
  final stack = _parseLegendStack(prefs.getString(PrefsKeys.legendVisitStack));
  if (stack.isNotEmpty && stack.first == legendName) return stack;
  stack.removeWhere((e) => e == legendName);
  stack.insert(0, legendName);
  await prefs.setString(PrefsKeys.legendVisitStack, jsonEncode(stack));
  return stack;
}
