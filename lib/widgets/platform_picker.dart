import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../constants/api_constants.dart';
import '../utils/formatting/platform_utils.dart';
import 'pill_segments.dart';

/// Platform selector: one capsule with a segment for each platform, each with
/// its icon and a short name.
class PlatformPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const PlatformPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PillSegments(
      options: [
        for (final p in ApiConstants.platforms)
          PillOption(
            label: ApiConstants.platformShortLabels[p] ?? p,
            semanticLabel: ApiConstants.labelFor(p),
            icon: (color) =>
                FaIcon(platformIconFor(p).icon, size: 12, color: color),
          ),
      ],
      selected: ApiConstants.platforms.indexOf(selected),
      onChanged: (i) => onChanged(ApiConstants.platforms[i]),
    );
  }
}
