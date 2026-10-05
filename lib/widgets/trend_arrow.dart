import 'package:flutter/material.dart';

/// Up / flat / down arrow for a change of [delta]. Exactly zero is flat; callers
/// that round first (so a tiny change reads as "unchanged") pass 0 themselves.
IconData trendIcon(double delta) => delta > 0
    ? Icons.trending_up
    : delta < 0
    ? Icons.trending_down
    : Icons.trending_flat;

/// A trend arrow for inline text. An icon rather than a text glyph so all three
/// states are the same size and take their colour on every platform (Android
/// draws `▶` as a fixed-colour emoji).
InlineSpan trendArrow(
  IconData icon,
  Color color, {
  double size = 14,
  EdgeInsets padding = const EdgeInsets.only(right: 4),
}) => WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: Padding(
    padding: padding,
    child: Icon(icon, size: size, color: color),
  ),
);
