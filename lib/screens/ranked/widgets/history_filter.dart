import 'package:flutter/material.dart';
import '../../../constants/legend_constants.dart';
import '../../../constants/map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart'
    show formatShortDate, formatSignedInt;
import '../../../utils/theme.dart';

enum HistoryMode { all, ranked, casual }

enum HistoryResult { any, wins, losses }

/// The ends of the RP-change slider. A handle left on an end means "no limit"
/// on that side, so a range is never silently capped at these values.
const int kFilterRpFloor = -100;
const int kFilterRpCeiling = 200;

/// What the History tab shows. Defaults to ranked games only — the headline
/// view — so "default" and "no filter" are different things; [activeCount]
/// counts what departs from the default.
class HistoryFilter {
  final HistoryMode mode;
  final HistoryResult result;
  final Set<String> legends;
  final Set<String> mapKeys;

  /// Local calendar days, both ends included. Null means any date.
  final DateTimeRange? dates;

  /// Bounds on a ranked game's RP change, either end optional. A casual game
  /// has no RP change, so it never passes while one of these is set.
  final int? minRp;
  final int? maxRp;

  const HistoryFilter({
    this.mode = HistoryMode.ranked,
    this.result = HistoryResult.any,
    this.legends = const {},
    this.mapKeys = const {},
    this.dates,
    this.minRp,
    this.maxRp,
  });

  HistoryFilter copyWith({
    HistoryMode? mode,
    HistoryResult? result,
    Set<String>? legends,
    Set<String>? mapKeys,
    DateTimeRange? dates,
    bool clearDates = false,
    int? minRp,
    int? maxRp,
    bool clearRp = false,
  }) => HistoryFilter(
    mode: mode ?? this.mode,
    result: result ?? this.result,
    legends: legends ?? this.legends,
    mapKeys: mapKeys ?? this.mapKeys,
    dates: clearDates ? null : (dates ?? this.dates),
    // [clearRp] drops the old bounds first; any bound passed is the new one.
    minRp: clearRp ? minRp : (minRp ?? this.minRp),
    maxRp: clearRp ? maxRp : (maxRp ?? this.maxRp),
  );

  bool get hasRpRange => minRp != null || maxRp != null;

  int get activeCount =>
      (mode != HistoryMode.ranked ? 1 : 0) +
      (result != HistoryResult.any ? 1 : 0) +
      (legends.isNotEmpty ? 1 : 0) +
      (mapKeys.isNotEmpty ? 1 : 0) +
      (dates != null ? 1 : 0) +
      (hasRpRange ? 1 : 0);

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
    // negative effective RP, so excluded games are neither.
    switch (result) {
      case HistoryResult.any:
        break;
      case HistoryResult.wins:
        if (m.effectiveRpChange <= 0) return false;
      case HistoryResult.losses:
        if (m.effectiveRpChange >= 0) return false;
    }
    if (legends.isNotEmpty && !selectsLegend(m.legend)) return false;
    if (mapKeys.isNotEmpty && !selectsMap(m.mapKey)) return false;
    final range = dates;
    if (range != null) {
      final start = m.startTime.toLocal();
      final day = DateTime(start.year, start.month, start.day);
      if (day.isBefore(_dayOf(range.start)) || day.isAfter(_dayOf(range.end))) {
        return false;
      }
    }
    if (hasRpRange) {
      if (!m.isRanked) return false;
      final rp = m.effectiveRpChange;
      if (minRp != null && rp < minRp!) return false;
      if (maxRp != null && rp > maxRp!) return false;
    }
    return true;
  }

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Whether [legend] is chosen, compared by canonical name.
  bool selectsLegend(String legend) {
    final c = canonicalLegendName(legend);
    return legends.any((l) => canonicalLegendName(l) == c);
  }

  /// Whether [mapKey] is chosen, compared by canonical key.
  bool selectsMap(String mapKey) {
    final c = canonicalMapKey(mapKey);
    return mapKeys.any((k) => canonicalMapKey(k) == c);
  }

  List<RankedMatch> apply(List<RankedMatch> all) => all.where(matches).toList();
}

/// Bottom sheet for editing a [HistoryFilter]. Changes apply live through
/// [onChanged]; [pool] supplies the legends and maps worth offering.
Future<void> showHistoryFilterSheet(
  BuildContext context, {
  required HistoryFilter filter,
  required List<RankedMatch> pool,
  required ValueChanged<HistoryFilter> onChanged,
}) {
  // One chip per canonical legend and map.
  final legends = {for (final m in pool) canonicalLegendName(m.legend)}.toList()
    ..sort();
  final mapByCanonical = <String, String>{};
  for (final m in pool) {
    mapByCanonical.putIfAbsent(canonicalMapKey(m.mapKey), () => m.mapKey);
  }
  final maps = mapByCanonical.values.toList()
    ..sort((a, b) => battleRoyaleMapName(a).compareTo(battleRoyaleMapName(b)));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Leaves the top of the screen showing, so it reads as a sheet.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
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

  /// Toggles [value] in [set], comparing by [canonical].
  Set<String> _toggled(
    Set<String> set,
    String value,
    String Function(String) canonical,
  ) {
    final c = canonical(value);
    return set.any((k) => canonical(k) == c)
        ? {
            for (final k in set)
              if (canonical(k) != c) k,
          }
        : {...set, c};
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTimeRange _lastDays(int days) {
    final today = _today();
    return DateTimeRange(
      start: DateTime(today.year, today.month, today.day - (days - 1)),
      end: today,
    );
  }

  static _DatePreset _presetOf(DateTimeRange? r) {
    if (r == null) return _DatePreset.any;
    for (final (preset, days) in [
      (_DatePreset.today, 1),
      (_DatePreset.week, 7),
      (_DatePreset.month, 30),
    ]) {
      final p = _lastDays(days);
      if (r.start == p.start && r.end == p.end) return preset;
    }
    return _DatePreset.custom;
  }

  String _datePresetLabel(_DatePreset p) {
    final r = _filter.dates;
    return switch (p) {
      _DatePreset.any => 'Any',
      _DatePreset.today => 'Today',
      _DatePreset.week => 'Last 7 days',
      _DatePreset.month => 'Last 30 days',
      _DatePreset.custom =>
        r != null && _presetOf(r) == _DatePreset.custom
            ? '${formatShortDate(r.start)} – ${formatShortDate(r.end)}'
            : 'Pick dates…',
    };
  }

  Future<void> _pickDate(_DatePreset p) async {
    switch (p) {
      case _DatePreset.any:
        _set(_filter.copyWith(clearDates: true));
      case _DatePreset.today:
        _set(_filter.copyWith(dates: _lastDays(1)));
      case _DatePreset.week:
        _set(_filter.copyWith(dates: _lastDays(7)));
      case _DatePreset.month:
        _set(_filter.copyWith(dates: _lastDays(30)));
      case _DatePreset.custom:
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2023),
          lastDate: _today(),
          initialDateRange: _filter.dates,
        );
        if (picked != null && mounted) {
          _set(
            _filter.copyWith(
              dates: DateTimeRange(
                start: DateTime(
                  picked.start.year,
                  picked.start.month,
                  picked.start.day,
                ),
                end: DateTime(
                  picked.end.year,
                  picked.end.month,
                  picked.end.day,
                ),
              ),
            ),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The button stays visible while the chips scroll.
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.lg,
                AppTheme.lg,
                AppTheme.lg,
                0,
              ),
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
                  const _Label('Date'),
                  _Chips<_DatePreset>(
                    values: _DatePreset.values,
                    label: _datePresetLabel,
                    selected: (v) => _presetOf(_filter.dates) == v,
                    onTap: _pickDate,
                  ),
                  const _Label('RP change (ranked games)'),
                  _RpRange(
                    filter: _filter,
                    onChanged: (min, max) => _set(
                      _filter.copyWith(clearRp: true, minRp: min, maxRp: max),
                    ),
                  ),
                  if (widget.mapKeys.isNotEmpty) ...[
                    const _Label('Map'),
                    _Chips<String>(
                      values: widget.mapKeys,
                      label: battleRoyaleMapName,
                      selected: _filter.selectsMap,
                      onTap: (v) => _set(
                        _filter.copyWith(
                          mapKeys: _toggled(
                            _filter.mapKeys,
                            v,
                            canonicalMapKey,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (widget.legends.isNotEmpty) ...[
                    const _Label('Legend'),
                    _Chips<String>(
                      values: widget.legends,
                      label: (v) => v,
                      selected: _filter.selectsLegend,
                      onTap: (v) => _set(
                        _filter.copyWith(
                          legends: _toggled(
                            _filter.legends,
                            v,
                            canonicalLegendName,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTheme.lg),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DatePreset { any, today, week, month, custom }

/// A two-handle slider for the RP change of a ranked game. A handle at an end
/// of the track means no limit on that side.
class _RpRange extends StatelessWidget {
  final HistoryFilter filter;
  final void Function(int? min, int? max) onChanged;
  const _RpRange({required this.filter, required this.onChanged});

  static String describe(int? min, int? max) {
    if (min == null && max == null) return 'Any';
    if (max == null) return '${formatSignedInt(min!)} or more';
    if (min == null) return '${formatSignedInt(max)} or less';
    return '${formatSignedInt(min)} to ${formatSignedInt(max)}';
  }

  @override
  Widget build(BuildContext context) {
    final values = RangeValues(
      (filter.minRp ?? kFilterRpFloor)
          .clamp(kFilterRpFloor, kFilterRpCeiling)
          .toDouble(),
      (filter.maxRp ?? kFilterRpCeiling)
          .clamp(kFilterRpFloor, kFilterRpCeiling)
          .toDouble(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          describe(filter.minRp, filter.maxRp),
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        RangeSlider(
          values: values,
          min: kFilterRpFloor.toDouble(),
          max: kFilterRpCeiling.toDouble(),
          divisions: (kFilterRpCeiling - kFilterRpFloor) ~/ 5,
          activeColor: AppTheme.accent,
          onChanged: (v) {
            final lo = v.start.round();
            final hi = v.end.round();
            onChanged(
              lo <= kFilterRpFloor ? null : lo,
              hi >= kFilterRpCeiling ? null : hi,
            );
          },
        ),
      ],
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
