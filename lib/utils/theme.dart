import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import '../models/player_stats.dart';

class AppTheme {
  /// Transparent system bars with light icons (the app is dark end-to-end).
  /// Applied in main(), and on Android also via the AppBarTheme and around the
  /// app shell: Flutter's default AppBar overlay style has a black nav bar that
  /// overrides main()'s and paints an opaque strip under the bottom bar below
  /// Android 15. Not applied on iOS, which never had that problem.
  static const systemOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static const bg = Color(0xFF0d1117);
  static const surface = Color(0xFF161b22);
  static const surface2 = Color(0xFF1c2330);
  static const accent = Color(0xFFd4722f);
  static const accent2 = Color(0xFFe8943a);
  static const textPrimary = Color(0xFFe6edf3);
  static const muted = Color(0xFF8b929c);
  static const green = Color(0xFF56d364);
  static const red = Color(0xFFe06c75);

  /// Green for a gain, red for a loss. Callers pass their own test for what
  /// counts as positive (some treat 0 as a gain, others don't).
  static Color signColor(bool positive) => positive ? green : red;
  static const blue = Color(0xFF79c0ff);
  static const orange = Color(0xFFffa657);
  static const shimmerHighlight = Color(0xFF2d3a4a);

  /// Gradient scrim overlays for hero images behind card content.
  static const cardScrimTop = Color(0x22000000);
  static const cardScrimBottom = Color(0xE60D1117);
  static const cardScrimStart = Color(0xD90D1117);
  static const cardScrimEnd = Color(0x44000000);

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  static const double radiusSm = 6;
  static const double radiusMd = 10;
  static const double radiusLg = 16;
  static const double radiusFull = 50;

  static const double iconSizeSmall = 14;
  static const double iconSizeMedium = 20;
  static const double iconSizeLarge = 32;
  static const double rankIconSize = 42;
  static const double newsImageHeight = 160;

  /// Height of the hero map image inside the map card.
  static const double mapCardImageHeight = 180;

  /// Vertical padding for summary tile rows (shared across tile, skeleton, error).
  static const double summaryTileVerticalPadding = 14;

  /// Duration for short UI transitions (pill/tab animations, etc).
  static const Duration shortAnimation = Duration(milliseconds: 200);

  // API returns status values in uppercase ('UP', 'DOWN', 'SLOW', 'PARTIAL').
  static Color statusColor(String status) => switch (status) {
    'UP' || 'OK' => green,
    'SLOW' => orange,
    'DOWN' => red,
    _ => muted,
  };

  static ThemeData get materialTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      foregroundColor: textPrimary,
      // Android only: on iOS the AppBar default (which sets statusBarBrightness)
      // must stay in effect.
      systemOverlayStyle: defaultTargetPlatform == TargetPlatform.android
          ? systemOverlayStyle
          : null,
    ),
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: accent2,
      surface: surface,
      error: red,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: textPrimary),
      bodyMedium: TextStyle(color: textPrimary),
      bodySmall: TextStyle(color: muted),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: accent,
      unselectedItemColor: muted,
      type: BottomNavigationBarType.fixed,
    ),
    cardTheme: const CardThemeData(color: surface),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: surface2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: surface2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: accent),
      ),
      hintStyle: const TextStyle(color: muted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: muted,
      indicatorColor: accent,
    ),
  );
}

/// Returns the color for a player's online presence indicator.
Color playerPresenceColor(PlayerStats stats) {
  if (stats.isInGame) return AppTheme.green;
  if (stats.isOnline) return AppTheme.orange;
  return AppTheme.red;
}
