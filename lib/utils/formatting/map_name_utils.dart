/// Converts a raw map-rotation key from the `/games` endpoint into a
/// human-readable name.
///
/// The endpoint returns keys like `olympus_rotation`, `storm_point_rotation`,
/// `kings_canyon_rotation`, `broken_moon_rotation`, or `UNKNOWN`. This strips the
/// trailing `_rotation`, splits on `_`, and title-cases each word.
///
///   `olympus_rotation`      → `Olympus`
///   `storm_point_rotation`  → `Storm Point`
///   `UNKNOWN` / empty       → `Unknown`
String formatRotationMapName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.toUpperCase() == 'UNKNOWN') return 'Unknown';

  var base = trimmed.toLowerCase();
  if (base.endsWith('_rotation')) {
    base = base.substring(0, base.length - '_rotation'.length);
  }

  final words = base
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1));

  final result = words.join(' ');
  return result.isEmpty ? 'Unknown' : result;
}
