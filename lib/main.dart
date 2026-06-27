import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'app.dart';
import 'env/env.dart';
import 'providers/api_provider.dart';
import 'providers/settings_provider.dart';
import 'services/api_service.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';
import 'utils/app_logger.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Desktop (Linux/Windows/macOS) has no native sqflite binding — use the FFI
  // factory. iOS/Android keep sqflite's native factory.
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  tz.initializeTimeZones();

  final prefs = await SharedPreferences.getInstance();
  await NotificationService.init();
  await BackgroundService.init();

  final apiService = ApiService(prefs);
  unawaited(apiService.warmup());

  final app = ProviderScope(
    overrides: [
      apiServiceProvider.overrideWithValue(apiService),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: const ApexLegendsApp(),
  );

  final dsn = Env.sentryDsn;

  if (dsn.isEmpty || !(Platform.isAndroid || Platform.isIOS)) {
    // No DSN configured, or not a supported mobile platform — Sentry's Crashpad
    // backend cannot reliably spawn its handler subprocess on desktop targets.
    _hookFlutterErrors(sentryFlutterHandler: null);
    FlutterNativeSplash.remove();
    runApp(app);
    return;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = dsn;
      // Never send IP addresses, device identifiers, or user identity.
      options.sendDefaultPii = false;
      options.maxBreadcrumbs = 50;
      // sentry_dio is not used, so Dio requests are not auto-instrumented —
      // no player names or UIDs can leak through HTTP breadcrumbs.
    },
    appRunner: () {
      // Chain our logger after Sentry sets its own FlutterError handler.
      _hookFlutterErrors(sentryFlutterHandler: FlutterError.onError);
      FlutterNativeSplash.remove();
      runApp(app);
    },
  );
}

/// Wires [FlutterError.onError] and [PlatformDispatcher.instance.onError]
/// through the app logger. When [sentryFlutterHandler] is set, it is called
/// after logging so crashes are also reported to Sentry.
void _hookFlutterErrors({
  void Function(FlutterErrorDetails)? sentryFlutterHandler,
}) {
  FlutterError.onError = (details) {
    log.e(
      'FlutterError: ${details.exceptionAsString()}',
      error: details.exception,
      stackTrace: details.stack,
    );
    if (sentryFlutterHandler != null) {
      sentryFlutterHandler(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    log.e('PlatformDispatcher error', error: error, stackTrace: stack);
    return false;
  };
}
