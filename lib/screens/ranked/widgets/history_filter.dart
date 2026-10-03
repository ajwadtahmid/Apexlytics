import 'package:flutter/material.dart';
import '../../../constants/map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/theme.dart';

enum HistoryMode { all, ranked, casual }

enum HistoryResult { any, wins, losses }

/// What the History tab shows. Defaults to ranked games only — the headline
/// view — so "default" and "no filter" are different things; [activeCount]
/// counts what departs from the default.
class HistoryFilter {
  final HistoryMode mode;
  final HistoryResult result;
  final Set<String> legends;
  final Set<String> mapKeys;

  const HistoryFilter({
    this.mode = HistoryMode.ranked,
    this.result = HistoryResult.any,
    this.legends = const {},
    this.mapKeys = const {},
  });

  HistoryFilter copyWith({
    HistoryMode? mode,
    HistoryResult? result,
    Set<String>? legends,
    Set<String>? mapKeys,
  }) => HistoryFilter(
    mode: mode ?? this.mode,
    result: result ?? this.result,
    legends: legends ?? this.legends,
    mapKeys: mapKeys ?? this.mapKeys,
  );

  int get activeCount =>
      (mode != HistoryMode.ranked ? 1 : 0) +
      (result != HistoryResult.any ? 1 : 0) +
      (legends.isNotEmpty ? 1 : 0) +
      (mapKeys.isNotEmpty ? 1 : 0);

  bool matches(RankedMatch m) {
    switch (mode) {
      case HistoryMode.all:
        break;
      case HistoryMode.ranked:
        if (!m.isRanked) return false;
      case HistoryMode.casual:
        if (m.isRanked) return false;
    }
    // Same definition as the day header and the win-rate chip: positive /
    // negative effective RP, so outliers and excluded games are neither.
    switch (result) {
      case HistoryResult.any:
        break;
      case HistoryResult.wins:
        if (m.effectiveRpChange <= 0) return false;
      case HistoryResult.losses:
        if (m.effectiveRpChange >= 0) return false;
    }
    if (legends.isNotEmpty && !legends.contains(m.legend)) return false;
    if (mapKeys.isNotEmpty && !mapKeys.contains(m.mapKey)) return false;
    return true;
  }

  List<RankedMatch> apply(List<RankedMatch> all) =>
      all.where(matches).toList();
}

/// Bottom sheet for editing a [HistoryFilter]. Changes apply live through
/// [onChanged]; [pool] supplies the legends and maps worth offering.
Future<void> showHistoryFilterSheet(
  BuildContext context, {
  required HistoryFilter filter,
  required List<RankedMatch> pool,
  required ValueChanged<HistoryFilter> onChanged,
}) {
  final legends = {for (final m in pool) m.legend}.toList()..sort();
  final maps = {for (final m in pool) m.mapKey}.toList()
    ..sort(
      (a, b) => battleRoyaleMapName(a).compareTo(battleRoyaleMapName(b)),
    );
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (_) => _FilterSheet(
      initial: filter,
      legends: legends,
      mapKeys: maps,
      onChanged: onChanged,
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  final HistoryFilter initial;
  final List<String> legends;
  final List<String> mapKeys;
  final ValueChanged<HistoryFilter> onChanged;
  const _FilterSheet({
    required this.initial,
    required this.legends,
    required this.mapKeys,
    required this.onChanged,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late HistoryFilter _filter = widget.initial;

  void _set(HistoryFilter f) {
    setState(() => _filter = f);
    widget.onChanged(f);
  }

  Set<String> _toggled(Set<String> set, String value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Filter',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _filter.activeCount == 0
                      ? null
                      : () => _set(const HistoryFilter()),
                  child: const Text('Reset'),
                ),
              ],
            ),
            const _Label('Mode'),
            _Chips<HistoryMode>(
              values: HistoryMode.values,
              label: (v) => switch (v) {
                HistoryMode.all => 'All',
                HistoryMode.ranked => 'Ranked',
                HistoryMode.casual => 'Casual',
              },
              selected: (v) => _filter.mode == v,
              onTap: (v) => _set(_filter.copyWith(mode: v)),
            ),
            const _Label('Result (ranked games)'),
            _Chips<HistoryResult>(
              values: HistoryResult.values,
              label: (v) => switch (v) {
                HistoryResult.any => 'Any',
                HistoryResult.wins => 'Wins',
                HistoryResult.losses => 'Losses',
              },
              selected: (v) => _filter.result == v,
              onTap: (v) => _set(_filter.copyWith(result: v)),
            ),
            if (widget.mapKeys.isNotEmpty) ...[
              const _Label('Map'),
              _Chips<String>(
                values: widget.mapKeys,
                label: battleRoyaleMapName,
                selected: _filter.mapKeys.contains,
                onTap: (v) =>
                    _set(_filter.copyWith(mapKeys: _toggled(_filter.mapKeys, v))),
              ),
            ],
            if (widget.legends.isNotEmpty) ...[
              const _Label('Legend'),
              _Chips<String>(
                values: widget.legends,
                label: (v) => v,
                selected: _filter.legends.contains,
                onTap: (v) =>
                    _set(_filter.copyWith(legends: _toggled(_filter.legends, v))),
              ),
            ],
            const SizedBox(height: AppTheme.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppTheme.md, bottom: AppTheme.sm),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppTheme.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _Chips<T> extends StatelessWidget {
  final List<T> values;
  final String Function(T) label;
  final bool Function(T) selected;
  final ValueChanged<T> onTap;
  const _Chips({
    required this.values,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppTheme.sm,
      runSpacing: AppTheme.sm,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: selected(v),
            onSelected: (_) => onTap(v),
            showCheckmark: false,
            selectedColor: AppTheme.accent.withAlpha(50),
            backgroundColor: AppTheme.surface2,
            side: BorderSide(
              color: selected(v) ? AppTheme.accent : Colors.transparent,
            ),
            labelStyle: TextStyle(
              color: selected(v) ? AppTheme.accent : AppTheme.textPrimary,
              fontSize: 13,
            ),
          ),
      ],
    );
  }
}
