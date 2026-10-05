import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Small muted dot for separating inline text, e.g. "Level 500 • Gold II".
/// An icon rather than a `•` character so it takes the colour and size on
/// every platform instead of depending on the font's glyph.
const separatorDot = WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: Padding(
    padding: EdgeInsets.symmetric(horizontal: 8),
    child: Icon(Icons.circle, size: 4, color: AppTheme.muted),
  ),
);
