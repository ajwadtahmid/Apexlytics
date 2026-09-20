import 'package:flutter/widgets.dart' show Color;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../theme.dart';

/// Icon + brand color for an `ApiConstants.platforms` code (`PC`, `PS4`,
/// `X1`, `SWITCH`). Unrecognised codes fall back to the PC/desktop look.
///
/// FA6's free tier has no dedicated Switch glyph, so `SWITCH` reuses the
/// generic gamepad icon — that's a platform limitation, not an oversight.
({FaIconData icon, Color color}) platformIconFor(String platformKey) =>
    switch (platformKey) {
      'PS4' => (icon: FontAwesomeIcons.playstation, color: AppTheme.blue),
      'X1' => (icon: FontAwesomeIcons.xbox, color: AppTheme.green),
      'SWITCH' => (icon: FontAwesomeIcons.gamepad, color: AppTheme.red),
      _ => (icon: FontAwesomeIcons.desktop, color: AppTheme.muted),
    };
