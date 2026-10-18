import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_provider.dart';
import 'ranked_provider.dart';

/// What the app keeps on the device, as the Data section of Settings shows it.
class StorageUsage {
  /// Recorded games, across every profile, and the space their database takes.
  final int games;
  final int historyBytes;

  /// Saved server responses (offline copies), and about how large they are.
  final int cachedResponses;
  final int cacheBytes;

  const StorageUsage({
    required this.games,
    required this.historyBytes,
    required this.cachedResponses,
    required this.cacheBytes,
  });
}

/// Counted afresh whenever the Data section asks (see `CacheSettingsSection`),
/// and after the cache is cleared.
final storageUsageProvider = FutureProvider.autoDispose<StorageUsage>((
  ref,
) async {
  final store = ref.watch(rankedHistoryStoreProvider);
  final cache = ref.watch(apiServiceProvider).cacheUsage;
  return StorageUsage(
    games: await store.countStartedSince(null),
    historyBytes: await store.storageBytes(),
    cachedResponses: cache.entries,
    cacheBytes: cache.bytes,
  );
});
