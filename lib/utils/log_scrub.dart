import '../constants/api_constants.dart';

/// Removes what must not leave the device in a bug report: UIDs, saved player
/// names, email addresses, the account name inside a file path, and the values
/// of query parameters that carry a player or a key.
///
/// Log calls already follow a rule of never passing these in; this is the
/// second line of defence for the text that rule misses (an exception message
/// quoting a URL, say).
///
/// [names] are exact strings to hide wherever they appear, ignoring case: the
/// saved profiles' names and the favorites'. Ones under 3 characters are
/// skipped, since they would match inside ordinary words.
String scrubForReport(String text, {Iterable<String> names = const []}) {
  var out = text;
  for (final name in names) {
    final trimmed = name.trim();
    if (trimmed.length < 3) continue;
    out = out.replaceAll(
      RegExp(RegExp.escape(trimmed), caseSensitive: false),
      '<name>',
    );
  }
  out = out
      .replaceAllMapped(
        RegExp(
          r'\b(uid|name|player|query|token|key|auth)=[^&\s"]+',
          caseSensitive: false,
        ),
        (m) => '${m[1]}=<redacted>',
      )
      .replaceAll(RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+'), '<email>')
      .replaceAll(ApiConstants.uidPattern, '<uid>')
      .replaceAllMapped(
        RegExp(r'(/home/|/Users/|[A-Za-z]:\\Users\\)[^/\\\s]+'),
        (m) => '${m[1]}<user>',
      );
  return out;
}
