import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/api_constants.dart';
import '../../providers/api_provider.dart';
import '../../providers/owner_provider.dart';
import '../../utils/notifications.dart';
import '../../utils/theme.dart';
import '../../widgets/widgets.dart' show SettingsCard;

/// Dedicated "about" destination reached from Settings — version, release
/// notes, store rating, data-source credits, privacy policy, and attribution.
/// Reads as a plain, static info list (no per-row leading icons, unlike the
/// rest of Settings) — links keep only the trailing open-in-new glyph that
/// marks them as outgoing, same as `_SupportRow`.
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  static const _ownerTapCount = 7;
  static const _tapWindow = Duration(seconds: 3);

  int _taps = 0;
  DateTime? _lastTap;

  void _onVersionTap(String version) {
    final now = DateTime.now();
    final last = _lastTap;
    _taps = last != null && now.difference(last) <= _tapWindow ? _taps + 1 : 1;
    _lastTap = now;

    if (_taps >= _ownerTapCount) {
      _taps = 0;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const _OwnerDialog(),
        ),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref
        .watch(packageInfoProvider)
        .whenOrNull(data: (info) => info);
    final version = info?.version ?? '—';

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          const _SectionHeader('App'),
          SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  onTap: () => _onVersionTap(version),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Version', style: TextStyle(fontSize: 14)),
                      ),
                      Text(
                        version,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppTheme.surface2, height: 24),
                const _LinkRow(
                  label: 'Release notes',
                  url: ApiConstants.releaseNotesUrl,
                ),
                if (Platform.isAndroid || Platform.isIOS) ...[
                  const Divider(color: AppTheme.surface2, height: 24),
                  _LinkRow(
                    label: 'Rate Apexlytics',
                    url: Platform.isAndroid
                        ? ApiConstants.playStoreUrl
                        : ApiConstants.appStoreUrl,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppTheme.md),

          const _SectionHeader('Data credits'),
          const SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CreditRow(
                  label: 'apexlegendsstatus.com',
                  subtitle:
                      'Server status. You can check this website for more information.',
                  url: ApiConstants.apexStatusUrl,
                ),
                Divider(color: AppTheme.surface2, height: 24),
                _CreditRow(
                  label: 'apexlegendsapi.com',
                  subtitle:
                      'Player stats & legend data are provided by this API.',
                  url: ApiConstants.apexApiUrl,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.md),

          const _SectionHeader('Legal'),
          const SettingsCard(
            child: _LinkRow(
              label: 'Privacy policy',
              url: ApiConstants.privacyPolicyUrl,
            ),
          ),
          const SizedBox(height: AppTheme.xl),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.lg),
            child: Text(
              'Unofficial companion app. Not affiliated with or endorsed by '
              'Electronic Arts or Respawn Entertainment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.sm),
          const Center(
            child: Text(
              'Made by Ajwad Tahmid Ayon',
              style: TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ),
          const SizedBox(height: AppTheme.xl),
        ],
      ),
    );
  }
}

/// Reached by tapping the version row [_AboutScreenState._ownerTapCount]
/// times. Unlocks owner mode with a token, or removes it if already unlocked.
class _OwnerDialog extends ConsumerStatefulWidget {
  const _OwnerDialog();

  @override
  ConsumerState<_OwnerDialog> createState() => _OwnerDialogState();
}

class _OwnerDialogState extends ConsumerState<_OwnerDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      final ok = await ref
          .read(ownerUnlockedProvider.notifier)
          .unlock(_controller.text);
      if (!ok) error = 'Token not accepted.';
    } on OwnerTokenStorageException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Couldn\'t reach the server. Try again.';
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
      context.showMessage('Owner mode on');
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _lock() async {
    await ref.read(ownerUnlockedProvider.notifier).lock();
    if (!mounted) return;
    Navigator.pop(context);
    context.showMessage('Owner mode off');
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = ref.watch(ownerUnlockedProvider);
    return AlertDialog(
      title: const Text('Owner mode'),
      content: unlocked
          ? const Text('This device is unlocked.')
          : TextField(
              controller: _controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'Token',
                errorText: _error,
              ),
              onSubmitted: (_) => _unlock(),
            ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (unlocked)
          TextButton(onPressed: _lock, child: const Text('Remove'))
        else
          TextButton(
            onPressed: _busy ? null : _unlock,
            child: const Text('Unlock'),
          ),
      ],
    );
  }
}

/// Plain text section header — no icon, unlike [SectionLabel] used elsewhere
/// in Settings, to keep this page reading as a flat info list.
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Single-line external link row. Same text treatment and trailing
/// open-in-new glyph as `_SupportRow` in `settings_screen.dart` — the one
/// icon this page keeps, since it's the standard outgoing-link affordance
/// rather than decoration.
class _LinkRow extends StatelessWidget {
  final String label;
  final String url;

  const _LinkRow({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: () => unawaited(
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            ),
          ),
          const Icon(Icons.open_in_new, color: AppTheme.muted, size: 14),
        ],
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final String url;

  const _CreditRow({
    required this.label,
    required this.subtitle,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: () => unawaited(
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.sm),
          const Icon(Icons.open_in_new, color: AppTheme.muted, size: 14),
        ],
      ),
    );
  }
}
