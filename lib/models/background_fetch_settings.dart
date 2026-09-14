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

  /// Returns null if no modes are enabled or all active modes have 0 timing.
  static BackgroundFetchSettings? fromPrefs(SharedPreferences prefs) {
    final notifyPubs = prefs.getBool(PrefsKeys.notifyPubsMapRotation) ?? false;
    final notifyRanked =
        prefs.getBool(PrefsKeys.notifyRankedMapRotation) ?? false;
    final notifyMixtape =
        prefs.getBool(PrefsKeys.notifyMixtapeMapRotation) ?? false;
    final notifyWildcard =
        prefs.getBool(PrefsKeys.notifyWildcardMapRotation) ?? false;
    if (!notifyPubs && !notifyRanked && !notifyMixtape && !notifyWildcard) {
      return null;
    }

    final legacy = prefs.getInt(PrefsKeys.mapNotifyMinutes) ?? 0;
    final ranked = prefs.getInt(PrefsKeys.rankedNotifyMinutes) ?? legacy;
    final pubs = prefs.getInt(PrefsKeys.pubsNotifyMinutes) ?? legacy;
    final mixtape = prefs.getInt(PrefsKeys.mixtapeNotifyMinutes) ?? legacy;
    final wildcard = prefs.getInt(PrefsKeys.wildcardNotifyMinutes) ?? 0;

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
        prefs.getString(PrefsKeys.favoriteRankedMapNames),
      ),
      favoritePubsMapNames: parseStringList(
        prefs.getString(PrefsKeys.favoritePubsMapNames),
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
