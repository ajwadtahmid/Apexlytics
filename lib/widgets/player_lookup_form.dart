import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import '../providers/api_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/error_messages.dart';
import '../utils/formatting/search_utils.dart';
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

  const PlayerLookupForm({
    super.key,
    required this.submitLabel,
    this.onSuccess,
    this.onPlayerFound,
    this.initialName,
    this.initialPlatform,
  });

  @override
  ConsumerState<PlayerLookupForm> createState() => _PlayerLookupFormState();
}

class _PlayerLookupFormState extends ConsumerState<PlayerLookupForm> {
  final _controller = TextEditingController();
  String _platform = ApiConstants.defaultPlatform;
  bool _loading = false;
  String? _error;
  bool _searchByUid = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null) {
      _controller.text = widget.initialName!;
      _platform = widget.initialPlatform ?? ApiConstants.defaultPlatform;
    } else {
      final settings = ref.read(playerSettingsProvider);
      if (settings.isPlayerSet) {
        _controller.text = settings.name;
        _platform = settings.platform;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleUidSearch(bool value) async {
    if (value && !_searchByUid) {
      await showUidWarningIfNeeded(context, ref);
    }
    if (!mounted) return;
    setState(() {
      _searchByUid = value;
      // Flags an existing non-digit value rather than clearing it.
      _error = (value && !isDigitsOnly(_controller.text))
          ? 'UID must contain digits only.'
          : null;
    });
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
    if (!ref
        .read(refreshCooldownProvider)
        .tryFire(playerRefreshKey(_platform, query))) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final String name;
      final String uid;
      if (_searchByUid) {
        final statsResult = await ref
            .read(playerServiceProvider)
            .getPlayerStatsByUid(query, _platform);
        name = statsResult.data.name;
        uid = statsResult.data.uid;
      } else {
        final statsResult = await ref
            .read(playerServiceProvider)
            .getPlayerStats(query, _platform);
        name = statsResult.data.name;
        uid = statsResult.data.uid;
      }
      if (widget.onPlayerFound != null) {
        await widget.onPlayerFound!(name, uid, _platform);
      } else {
        await ref
            .read(playerSettingsProvider.notifier)
            .setPlayer(name, uid, _platform);
      }
      widget.onSuccess?.call();
    } catch (e) {
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
          // Clears the toggle-time "digits only" message as soon as the user
          // starts fixing it, instead of leaving a stale error on screen.
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
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
          onChanged: (p) => setState(() => _platform = p),
          expanded: true,
        ),
        const SizedBox(height: AppTheme.sm),
        UidSearchToggle(value: _searchByUid, onChanged: _toggleUidSearch),
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
