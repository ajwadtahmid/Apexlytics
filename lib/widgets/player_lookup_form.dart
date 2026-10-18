import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/ui_strings.dart';
import '../providers/api_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/error_messages.dart';
import '../utils/formatting/search_utils.dart';
import '../utils/lookup_form_state.dart';
import '../utils/theme.dart';
import '../utils/uid_warning_dialog.dart';
import 'lookup_card.dart';
import 'uid_search_toggle.dart' show isDigitsOnly;

/// Shared player-lookup form used in the initial setup view and profile manager.
/// [onPlayerFound] — if supplied, called instead of the default `setPlayer` call,
/// letting callers choose which profile slot to write to.
class PlayerLookupForm extends ConsumerStatefulWidget {
  final String submitLabel;
  final VoidCallback? onSuccess;
  final Future<void> Function(String name, String uid, String platform)?
  onPlayerFound;
  final String? initialName;
  final String? initialPlatform;

  /// UID of the profile being edited, shown when switching to UID search. Adding starts blank.
  final String? initialUid;

  const PlayerLookupForm({
    super.key,
    required this.submitLabel,
    this.onSuccess,
    this.onPlayerFound,
    this.initialName,
    this.initialPlatform,
    this.initialUid,
  });

  @override
  ConsumerState<PlayerLookupForm> createState() => _PlayerLookupFormState();
}

class _PlayerLookupFormState extends ConsumerState<PlayerLookupForm> {
  late final LookupFormState _lookup;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lookup = LookupFormState(
      beforeUidMode: () => showUidWarningIfNeeded(context, ref),
      name: widget.initialName,
      platform: widget.initialPlatform,
      uid: widget.initialUid,
    )..addListener(_clearError);
  }

  @override
  void dispose() {
    _lookup.dispose();
    super.dispose();
  }

  /// A change of mode or platform makes an old error stale.
  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _submit() async {
    if (_loading) return;
    final query = _lookup.controller.text.trim();
    final byUid = _lookup.byUid;
    final platform = _lookup.platform;
    if (query.isEmpty) {
      setState(
        () => _error = byUid ? 'Enter a player UID.' : 'Enter a player name.',
      );
      return;
    }
    if (byUid && !isDigitsOnly(query)) {
      // Formatters should already guarantee this — belt and suspenders.
      setState(() => _error = 'UID must contain digits only.');
      return;
    }
    // The same key the favorites and result-page refreshes fire under, so all
    // three share one cooldown window per player.
    final cooldown = ref.read(refreshCooldownProvider);
    final cooldownKey = playerRefreshKey(platform, query);
    if (!cooldown.tryFire(cooldownKey)) {
      setState(() => _error = null);
      _lookup.showNotice(lookupCooldownNotice);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    _lookup.clearNotice();
    try {
      final service = ref.read(playerServiceProvider);
      final stats =
          (byUid
                  ? await service.getPlayerStatsByUid(query, platform)
                  : await service.getPlayerStats(query, platform))
              .data;
      // A 200 with no player would save an "Unknown" profile with no UID.
      if (stats.uid.isEmpty) {
        throw AppException(
          byUid
              ? 'Player not found. Check the UID and platform.'
              : 'Player not found. Check the name and platform.',
        );
      }
      // Closed while the lookup ran: nothing to save, and the caller has
      // moved on (it may now be editing another profile).
      if (!mounted) return;
      if (widget.onPlayerFound != null) {
        await widget.onPlayerFound!(stats.name, stats.uid, platform);
      } else {
        await ref
            .read(playerSettingsProvider.notifier)
            .setPlayer(stats.name, stats.uid, platform);
      }
      widget.onSuccess?.call();
    } catch (e) {
      // A failed attempt doesn't hold the cooldown, so a retry isn't swallowed.
      cooldown.release(cooldownKey);
      final msg = friendlyError(e);
      if (mounted) setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LookupCard(
          state: _lookup,
          onSubmit: _submit,
          error: _error,
          // Clear an old error once the user types.
          onChanged: _clearError,
        ),
        const SizedBox(height: AppTheme.lg),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(widget.submitLabel),
        ),
      ],
    );
  }
}
