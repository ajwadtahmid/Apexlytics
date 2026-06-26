import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/api_service.dart';
import '../services/map_service.dart';
import '../services/server_service.dart';
import '../services/player_service.dart';
import '../services/news_service.dart';
import '../services/predator_service.dart';
import '../services/games_service.dart';
import '../services/approved_uids_service.dart';

// Overridden in main() with the shared instance created before runApp.
final apiServiceProvider = Provider<ApiService>(
  (ref) => throw UnimplementedError(),
);

final mapServiceProvider = Provider<MapService>(
  (ref) => MapService(ref.watch(apiServiceProvider)),
);

final serverServiceProvider = Provider<ServerService>(
  (ref) => ServerService(ref.watch(apiServiceProvider)),
);

final playerServiceProvider = Provider<PlayerService>(
  (ref) => PlayerService(ref.watch(apiServiceProvider)),
);

final newsServiceProvider = Provider<NewsService>(
  (ref) => NewsService(ref.watch(apiServiceProvider)),
);

final predatorServiceProvider = Provider<PredatorService>(
  (ref) => PredatorService(ref.watch(apiServiceProvider)),
);

final gamesServiceProvider = Provider<GamesService>(
  (ref) => GamesService(ref.watch(apiServiceProvider)),
);

final approvedUidsServiceProvider = Provider<ApprovedUidsService>(
  (ref) => ApprovedUidsService(ref.watch(apiServiceProvider)),
);

/// Cached app version info — avoids re-firing the platform channel on every
/// build of SettingsScreen.
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);
