import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/map_rotation.dart';
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';
import 'map_hero_image.dart';

const _kModeRanked = 'Ranked';
const _kModePubs = 'Pubs';
const _kModeWildcard = 'Wildcards';
const _kModeMixtape = 'Mixtape';

/// Map rotation card: mode picker + the selected mode's current/next map,
/// with a live countdown. Owns its own mode-selection state since switching
/// modes is purely a display concern, not something the rest of Home cares
/// about.
class MapRotationCard extends StatefulWidget {
  final MapRotation rotation;
  final VoidCallback? onExpired;

  const MapRotationCard({super.key, required this.rotation, this.onExpired});

  @override
  State<MapRotationCard> createState() => _MapRotationCardState();
}

class _MapRotationCardState extends State<MapRotationCard> {
  int _modeIndex = 0;

  List<_ModeData> _buildModes(MapRotation rotation) => [
    _ModeData(
      label: _kModeRanked,
      current: rotation.rankedCurrent,
      next: rotation.rankedNext,
    ),
    _ModeData(
      label: _kModePubs,
      current: rotation.battleRoyaleCurrent,
      next: rotation.battleRoyaleNext,
    ),
    if (rotation.wildcardCurrent != null && rotation.wildcardNext != null)
      _ModeData(
        label: _kModeWildcard,
        current: rotation.wildcardCurrent!,
        next: rotation.wildcardNext!,
      ),
    if (rotation.ltmCurrent != null && rotation.ltmNext != null)
      _ModeData(
        label: _kModeMixtape,
        current: rotation.ltmCurrent!,
        next: rotation.ltmNext!,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final modes = _buildModes(widget.rotation);
    if (modes.isEmpty) return const SizedBox.shrink();
    final idx = _modeIndex.clamp(0, modes.length - 1);
    return Column(
      children: [
        _ModePicker(
          modes: modes.map((m) => m.label).toList(),
          selected: idx,
          onSelect: (i) => setState(() => _modeIndex = i),
        ),
        const SizedBox(height: AppTheme.md),
        _MapCard(mode: modes[idx], onExpired: widget.onExpired),
      ],
    );
  }
}

class _ModeData {
  final String label;
  final MapMode current;
  final MapMode next;
  const _ModeData({required this.label, required this.current, required this.next});
}

// ── Mode picker ───────────────────────────────────────────────────────────────

class _ModePicker extends StatelessWidget {
  final List<String> modes;
  final int selected;
  final ValueChanged<int> onSelect;

  const _ModePicker({
    required this.modes,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(4),
      radius: AppTheme.radiusFull,
      child: Row(
        children: List.generate(modes.length, (i) {
          final active = i == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: AppTheme.shortAnimation,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? AppTheme.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  modes[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active ? Colors.white : AppTheme.muted,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Map card ──────────────────────────────────────────────────────────────────

const _kCountdownTickInterval = Duration(seconds: 1);

class _MapCard extends StatefulWidget {
  final _ModeData mode;
  final VoidCallback? onExpired;
  const _MapCard({required this.mode, this.onExpired});

  @override
  State<_MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<_MapCard> {
  late int _remaining;
  late DateTime _startedAt;
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _reset(widget.mode.current.remainingSecs);
  }

  @override
  void didUpdateWidget(_MapCard old) {
    super.didUpdateWidget(old);
    if (old.mode.label != widget.mode.label ||
        old.mode.current.map != widget.mode.current.map ||
        old.mode.current.remainingSecs != widget.mode.current.remainingSecs) {
      _reset(widget.mode.current.remainingSecs);
    }
  }

  void _reset(int secs) {
    _expired = false;
    _timer?.cancel();
    _remaining = secs;
    _startedAt = DateTime.now();
    _timer = Timer.periodic(_kCountdownTickInterval, (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_startedAt).inSeconds;
      final newRemaining = (secs - elapsed).clamp(0, secs);
      if (newRemaining != _remaining) {
        setState(() => _remaining = newRemaining);
      }
      if (newRemaining == 0 && !_expired) {
        _expired = true;
        _timer?.cancel();
        widget.onExpired?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static final _endTimeFormat = DateFormat('h:mm a');

  static String _formatCountdown(int secs) {
    final d = secs ~/ 86400;
    final h = (secs % 86400) ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (d > 0) {
      return '${d}d ${h}h';
    }
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String _formatEndTime(int remainingSecs) {
    final end = DateTime.now().add(Duration(seconds: remainingSecs));
    return _endTimeFormat.format(end);
  }

  static String _formatMapDisplay(String mapName, String? eventName, bool isMixtape) {
    if (isMixtape && eventName != null && eventName.isNotEmpty) {
      return '$mapName ($eventName)';
    }
    return mapName;
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.mode.current;
    final next = widget.mode.next;
    final isMixtape = widget.mode.label == _kModeMixtape;

    return SurfaceCard(
      radius: AppTheme.radiusLg,
      clip: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MapHeroImage(assetUrl: current.asset),
          Padding(
            padding: const EdgeInsets.all(AppTheme.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.mode.label.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: AppTheme.xs),
                Text(
                  _formatMapDisplay(current.map, current.eventName, isMixtape),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppTheme.sm),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: AppTheme.accent, size: 14),
                    const SizedBox(width: AppTheme.xs),
                    Text(
                      '${_formatCountdown(_remaining)} remaining',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(color: AppTheme.surface2, height: 1),
                const SizedBox(height: 10),
                _NextMapRow(
                  next: next,
                  remaining: _remaining,
                  isMixtape: isMixtape,
                  formatEndTime: _formatEndTime,
                  formatMapDisplay: _formatMapDisplay,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Next map row ──────────────────────────────────────────────────────────────

class _NextMapRow extends StatelessWidget {
  final MapMode next;
  final int remaining;
  final bool isMixtape;
  final String Function(int) formatEndTime;
  final String Function(String, String?, bool) formatMapDisplay;

  const _NextMapRow({
    required this.next,
    required this.remaining,
    required this.isMixtape,
    required this.formatEndTime,
    required this.formatMapDisplay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'UP NEXT',
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              'Starts at ${formatEndTime(remaining)}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.xs),
        Row(
          children: [
            const Icon(Icons.arrow_forward, size: 14, color: AppTheme.muted),
            const SizedBox(width: AppTheme.xs),
            Expanded(
              child: Text(
                formatMapDisplay(next.map, next.eventName, isMixtape),
                style: const TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
