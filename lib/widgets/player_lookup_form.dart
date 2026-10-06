import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import '../constants/ui_strings.dart';
import '../providers/api_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/error_messages.dart';
import '../utils/formatting/search_utils.dart';
import '../utils/lookup_drafts.dart';
import '../utils/theme.dart';
import '../utils/uid_warning_dialog.dart';
import 'platform_picker.dart';
import 'uid_search_toggle.dart';

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
  final _controller = TextEditingController();
  final _drafts = LookupDrafts();
  String _platform = ApiConstants.defaultPlatform;
  bool _loading = false;
  String? _error;

  /// A non-error heads-up (mode switched, refused toggle, throttled tap), in the accent colour.
  String? _notice;
  bool _searchByUid = false;

  /// UID search is on only because Switch is selected; leaving Switch turns it off again.
  /// If it was already on, it stays on.
  bool _uidForcedBySwitch = false;

  @override
  void initState() {
    super.initState();
    // Only an edit starts filled in; adding starts blank.
    final name = widget.initialName;
    if (name != null) {
      _platform = widget.initialPlatform ?? ApiConstants.defaultPlatform;
      _drafts.stash(uid: false, text: name);
      _drafts.stash(uid: true, text: widget.initialUid ?? '');
    }
    // Opened on Switch (editing one): UID search is forced, so leaving Switch returns to name.
    _searchByUid = _uidForcedBySwitch = ApiConstants.isUidOnly(_platform);
    setFieldText(_controller, _drafts.draftFor(uid: _searchByUid));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleUidSearch(bool value) async {
    if (value == _searchByUid) return;
    if (!value && ApiConstants.isUidOnly(_platform)) {
      // Switch is UID-only.
      setState(() {
        _error = null;
        _notice = switchNeedsUidWarning;
      });
      return;
    }
    await _setSearchByUid(value);
  }

  /// Switches the field between its name and UID drafts.
  Future<void> _setSearchByUid(bool value) async {
    if (value && !_searchByUid) {
      await showUidWarningIfNeeded(context, ref);
    }
    if (!mounted) return;
    setState(() {
      setFieldText(
        _controller,
        _drafts.swapTo(uid: value, current: _controller.text),
      );
      _searchByUid = value;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _selectPlatform(String platform) async {
    setState(() {
      _platform = platform;
      _error = null;
      _notice = null;
    });
    if (ApiConstants.isUidOnly(platform)) {
      if (_searchByUid) return;
      _uidForcedBySwitch = true;
      await _setSearchByUid(true);
      if (mounted) setState(() => _notice = switchAutoUidNotice);
    } else if (_uidForcedBySwitch) {
      // Leaving Switch: restore the toggle.
      _uidForcedBySwitch = false;
      await _setSearchByUid(false);
    }
  }

  Future<void> _submit() async {
    if (_loading) return;
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(
        () => _error = _searchByUid
            ? 'Enter a player UID.'
            : 'Enter a player name.',
      );
      return;
    }
    if (_searchByUid && !isDigitsOnly(query)) {
      // Formatters should already guarantee this — belt and suspenders.
      setState(() => _error = 'UID must contain digits only.');
      return;
    }
    // The same key the favorites and result-page refreshes fire under, so all
    // three share one cooldown window per player.
    final cooldown = ref.read(refreshCooldownProvider);
    final cooldownKey = playerRefreshKey(_platform, query);
    if (!cooldown.tryFire(cooldownKey)) {
      setState(() {
        _error = null;
        _notice = lookupCooldownNotice;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final service = ref.read(playerServiceProvider);
      final stats =
          (_searchByUid
                  ? await service.getPlayerStatsByUid(query, _platform)
                  : await service.getPlayerStats(query, _platform))
              .data;
      // A 200 with no player would save an "Unknown" profile with no UID.
      if (stats.uid.isEmpty) {
        throw AppException(
          _searchByUid
              ? 'Player not found. Check the UID and platform.'
              : 'Player not found. Check the name and platform.',
        );
      }
      if (widget.onPlayerFound != null) {
        await widget.onPlayerFound!(stats.name, stats.uid, _platform);
      } else {
        await ref
            .read(playerSettingsProvider.notifier)
            .setPlayer(stats.name, stats.uid, _platform);
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
        TextField(
          controller: _controller,
          onSubmitted: (_) => _submit(),
          // Clear an old error or notice once the user types.
          onChanged: (_) {
            if (_error != null || _notice != null) {
              setState(() {
                _error = null;
                _notice = null;
              });
            }
          },
          textInputAction: TextInputAction.done,
          keyboardType: _searchByUid
              ? TextInputType.number
              : TextInputType.text,
          inputFormatters: _searchByUid ? uidOnlyInputFormatters : null,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: _searchByUid ? 'Numeric UID' : 'In-game name',
            prefixIcon: Icon(
              _searchByUid ? Icons.numbers : Icons.person_outline,
              color: AppTheme.muted,
            ),
          ),
        ),
        const SizedBox(height: AppTheme.md),
        PlatformPicker(
          selected: _platform,
          onChanged: _selectPlatform,
          expanded: true,
        ),
        const SizedBox(height: AppTheme.sm),
        UidSearchToggle(value: _searchByUid, onChanged: _toggleUidSearch),
        UidSuggestion(
          controller: _controller,
          searchByUid: _searchByUid,
          onUseUid: () => _toggleUidSearch(true),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppTheme.sm),
          Container(
            padding: const EdgeInsets.all(AppTheme.sm),
            decoration: BoxDecoration(
              color: AppTheme.red.withAlpha(30),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppTheme.red, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppTheme.red, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_notice != null) ...[
          const SizedBox(height: AppTheme.sm),
          Container(
            padding: const EdgeInsets.all(AppTheme.sm),
            decoration: BoxDecoration(
              color: AppTheme.accent.withAlpha(30),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppTheme.accent, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _notice!,
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
