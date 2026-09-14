import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/prefs_keys.dart';

List<String> _parseLegendStack(String? raw) {
  try {
    final list = jsonDecode(raw ?? '[]') as List;
    return list.whereType<String>().toList();
  } on FormatException {
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
