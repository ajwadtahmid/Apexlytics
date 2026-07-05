class ApiConstants {
  static const String defaultPlatform = 'PC';

  static const String apexStatusUrl = 'https://apexlegendsstatus.com';
  static const String apexApiUrl = 'https://apexlegendsapi.com';
  static const String eaNewsUrl =
      'https://www.ea.com/games/apex-legends/apex-legends/news';

  static const String privacyPolicyUrl =
      'https://ajwadtahmid.github.io/privacy-policies/Apexlytics.html';
  static const String releaseNotesUrl =
      'https://github.com/ajwadtahmid/Apexlytics/releases';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.ajwadtahmid.apexlytics';
  static const String appStoreUrl = 'https://apps.apple.com/app/id6778521764';

  static const String alsProfileBaseUrl =
      'https://apexlegendsstatus.com/profile/uid';
  static const List<String> platforms = ['PC', 'PS4', 'X1', 'SWITCH'];

  static const String mapRotationPath = '/maprotation';
  static const String mapRotationVersion = '2';

  static const String gamesPath = '/games';
  static const String approvedUidsPath = '/approved-uids';

  /// Rolling match-history window the `/games` endpoint serves per UID.
  static const int gamesHistoryLimit = 100;

  static const Map<String, String> platformLabels = {
    'PC': 'PC',
    'PS4': 'PlayStation',
    'X1': 'Xbox',
    'SWITCH': 'Nintendo Switch',
  };

  /// Returns the human-readable label for [platform], falling back to the
  /// raw platform code if no label is defined.
  static String labelFor(String platform) =>
      platformLabels[platform] ?? platform;
}
