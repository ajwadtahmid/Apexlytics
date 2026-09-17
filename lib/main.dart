import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show SystemChrome, SystemUiMode, SystemUiOverlayStyle;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
import 'utils/storage/api_cache_store.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Android 15+ applies edge-to-edge regardless of an opt-out past SDK 36, so
  // draw behind the system bars deliberately rather than let the OS force it
  // with unstyled bars. AppTheme (utils/theme.dart) is dark end-to-end, hence
  // light system-bar icons on transparent bars.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Desktop (Linux/Windows/macOS) has no native sqflite binding — use the FFI
  // factory. iOS/Android keep sqflite's native factory.
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  tz.initializeTimeZones();

  final prefs = await SharedPreferences.getInstance();
  // Binder IPC in these plugins blocks the main thread; deferring prevents ANR.
  unawaited(_initServices());

  // Its own small database (api_cache.db), independent of ranked_history.db —
  // see ApiCacheStore's doc comment. Moving cache entries out of prefs is
  // what keeps SharedPreferences.getInstance() above from having to parse up
  // to 150 arbitrary-sized cached responses synchronously on every launch.
  final apiService = ApiService(ApiCacheStore());
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
    runApp(app);
    return;
  }

  final packageInfo = await PackageInfo.fromPlatform();

  await SentryFlutter.init(
    (options) {
      options.dsn = dsn;
      // Ties every event to the exact app version/build so a reported crash
      // can be checked against a fix's release instead of guessed at from
      // commit timestamps.
      options.release =
          'apexlytics@${packageInfo.version}+${packageInfo.buildNumber}';
      options.dist = packageInfo.buildNumber;
      // Never send IP addresses, device identifiers, or user identity.
      options.sendDefaultPii = false;
      options.maxBreadcrumbs = 50;
      // sentry_dio is not used, so Dio requests are not auto-instrumented —
      // no player names or UIDs can leak through HTTP breadcrumbs.
    },
    appRunner: () {
      // Chain our logger after Sentry sets its own FlutterError and
      // PlatformDispatcher handlers, so an uncaught error still reaches
      // Sentry with its unhandled-error classification intact rather than
      // only via a log.e() breadcrumb.
      _hookFlutterErrors(
        sentryFlutterHandler: FlutterError.onError,
        sentryPlatformHandler: PlatformDispatcher.instance.onError,
      );
      runApp(app);
    },
  );
}

Future<void> _initServices() async {
  try {
    await NotificationService.init();
  } catch (e) {
    log.e('NotificationService.init failed', error: e);
  }
  try {
    await BackgroundService.init();
  } catch (e) {
    log.e('BackgroundService.init failed', error: e);
  }
}

/// Wires [FlutterError.onError] and [PlatformDispatcher.instance.onError]
/// through the app logger. When [sentryFlutterHandler] / [sentryPlatformHandler]
/// are set (Sentry's own handlers, captured by the caller before this
/// function replaces them), they are chained after logging so crashes keep
/// reaching Sentry with their original classification — without this, the
/// unconditional reassignment below silently replaced whatever
/// SentryFlutter.init had already installed, and async platform errors
/// would only reach Sentry indirectly, as a plain log.e() breadcrumb.
void _hookFlutterErrors({
  void Function(FlutterErrorDetails)? sentryFlutterHandler,
  bool Function(Object, StackTrace)? sentryPlatformHandler,
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
    return sentryPlatformHandler?.call(error, stack) ?? false;
  };
}
