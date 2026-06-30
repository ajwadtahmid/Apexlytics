import 'dart:async' show unawaited;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/map_rotation.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_logger.dart';
import 'notification_service.dart';

class MapNotificationService {
  MapNotificationService._();

  static void schedule(WidgetRef ref, MapRotation data) {
    final s = ref.read(playerSettingsProvider);
    final anyActive =
        (s.notifyRankedMapRotation && s.rankedNotifyMinutesBefore > 0) ||
        (s.notifyPubsMapRotation && s.pubsNotifyMinutesBefore > 0) ||
        (s.notifyMixtapeMapRotation && s.mixtapeNotifyMinutesBefore > 0) ||
        (s.notifyWildcardMapRotation && s.wildcardNotifyMinutesBefore > 0);
    if (anyActive) {
      // The cyclic rotation order (from /maps) lets every projected Ranked/Pubs
      // alert be named, not just the next one. Falls back to generic copy if the
      // sequence hasn't loaded yet.
      final seasonal = ref.read(seasonalMapsProvider).asData?.value;
      unawaited(NotificationService.scheduleAll(
        data,
        notifyRanked: s.notifyRankedMapRotation,
        rankedMinutesBefore: s.rankedNotifyMinutesBefore,
        notifyPubs: s.notifyPubsMapRotation,
        pubsMinutesBefore: s.pubsNotifyMinutesBefore,
        notifyMixtape: s.notifyMixtapeMapRotation,
        mixtapeMinutesBefore: s.mixtapeNotifyMinutesBefore,
        notifyWildcard: s.notifyWildcardMapRotation,
        wildcardMinutesBefore: s.wildcardNotifyMinutesBefore,
        favoriteRankedMapNames: s.favoriteRankedMapNames,
        favoritePubsMapNames: s.favoritePubsMapNames,
        rankedSequence: seasonal?.rankedNames ?? const [],
        pubsSequence: seasonal?.pubsNames ?? const [],
      ).catchError((Object e) {
        log.e('Notification scheduling failed', error: e);
      }));
    } else {
      unawaited(NotificationService.cancelAll());
    }
  }
}
