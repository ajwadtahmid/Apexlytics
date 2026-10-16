import 'package:shared_preferences/shared_preferences.dart';
import '../constants/prefs_keys.dart';
import '../utils/formatting/json_utils.dart';
import '../utils/formatting/map_alerts_utils.dart';

class BackgroundFetchSettings {
  final bool notifyPubs;
  final bool notifyRanked;
  final bool notifyMixtape;
  final bool notifyWildcard;
  final int rankedMinutesBefore;
  final int pubsMinutesBefore;
  final int mixtapeMinutesBefore;
  final int wildcardMinutesBefore;
  final List<String> favoriteRankedMapNames;
  final List<String> favoritePubsMapNames;

  const BackgroundFetchSettings({
    required this.notifyPubs,
    required this.notifyRanked,
    required this.notifyMixtape,
    required this.notifyWildcard,
    required this.rankedMinutesBefore,
    required this.pubsMinutesBefore,
    required this.mixtapeMinutesBefore,
    required this.wildcardMinutesBefore,
    required this.favoriteRankedMapNames,
    required this.favoritePubsMapNames,
  });

  // A wrong-typed value reads as absent: the typed getters throw, which would
  // stop every background fetch.
  static bool? _bool(SharedPreferences p, String key) {
    final v = p.get(key);
    return v is bool ? v : null;
  }

  static int? _int(SharedPreferences p, String key) {
    final v = p.get(key);
    return v is int ? v : null;
  }

  static String? _string(SharedPreferences p, String key) {
    final v = p.get(key);
    return v is String ? v : null;
  }

  /// Returns null if no modes are enabled or all active modes have 0 timing.
  static BackgroundFetchSettings? fromPrefs(SharedPreferences prefs) {
    final notifyPubs = _bool(prefs, PrefsKeys.notifyPubsMapRotation) ?? false;
    final notifyRanked =
        _bool(prefs, PrefsKeys.notifyRankedMapRotation) ?? false;
    final notifyMixtape =
        _bool(prefs, PrefsKeys.notifyMixtapeMapRotation) ?? false;
    final notifyWildcard =
        _bool(prefs, PrefsKeys.notifyWildcardMapRotation) ?? false;
    if (!notifyPubs && !notifyRanked && !notifyMixtape && !notifyWildcard) {
      return null;
    }

    final legacy = _int(prefs, PrefsKeys.mapNotifyMinutes) ?? 0;
    final ranked = _int(prefs, PrefsKeys.rankedNotifyMinutes) ?? legacy;
    final pubs = _int(prefs, PrefsKeys.pubsNotifyMinutes) ?? legacy;
    final mixtape = _int(prefs, PrefsKeys.mixtapeNotifyMinutes) ?? legacy;
    final wildcard = _int(prefs, PrefsKeys.wildcardNotifyMinutes) ?? 0;

    final anyTiming =
        (notifyRanked && ranked > 0) ||
        (notifyPubs && pubs > 0) ||
        (notifyMixtape && mixtape > 0) ||
        (notifyWildcard && wildcard > 0);
    if (!anyTiming) return null;

    return BackgroundFetchSettings(
      notifyPubs: notifyPubs,
      notifyRanked: notifyRanked,
      notifyMixtape: notifyMixtape,
      notifyWildcard: notifyWildcard,
      rankedMinutesBefore: ranked,
      pubsMinutesBefore: pubs,
      mixtapeMinutesBefore: mixtape,
      wildcardMinutesBefore: wildcard,
      favoriteRankedMapNames: parseStringList(
        _string(prefs, PrefsKeys.favoriteRankedMapNames),
      ),
      favoritePubsMapNames: parseStringList(
        _string(prefs, PrefsKeys.favoritePubsMapNames),
      ),
    );
  }

  /// The smallest active timing — used to size the background fetch interval.
  int get minActiveMinutes => calculateMinActiveNotificationInterval(
    notifyRanked: notifyRanked,
    rankedMinutes: rankedMinutesBefore,
    notifyPubs: notifyPubs,
    pubsMinutes: pubsMinutesBefore,
    notifyMixtape: notifyMixtape,
    mixtapeMinutes: mixtapeMinutesBefore,
    notifyWildcard: notifyWildcard,
    wildcardMinutes: wildcardMinutesBefore,
  );
}
