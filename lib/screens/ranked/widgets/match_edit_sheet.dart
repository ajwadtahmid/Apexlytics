import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants/legend_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../providers/ranked_provider.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/theme.dart';

/// Opens the correction form for [match]. Resolves to the updated match if a
/// correction was actually saved or cleared, or null if nothing changed, so
/// callers holding a stale copy of [match] (e.g. a detail sheet opened before
/// this one) can patch their own copy immediately rather than waiting on the
/// next fetch.
Future<RankedMatch?> showMatchEditSheet(
  BuildContext context,
  RankedMatch match,
) {
  return showModalBottomSheet<RankedMatch>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (_) => MatchEditSheet(match: match),
  );
}

/// Bounds enforced on a hand-entered RP change, derived from the model's
/// plausibility constants rather than restated. The `- 1` matters:
/// [isImplausibleRpChange] treats [kRankedOutlierThreshold] itself as a reset
/// artifact, so a correction of exactly `1000` used to be accepted here and
/// then silently neutralized to 0.
const int kMinEditableRpChange = kMinPlausibleRpChange;
const int kMaxEditableRpChange = kRankedOutlierThreshold - 1;

/// One editable numeric stat: its stored column, form label, and a
/// field-specific range check for a human-readable error.
class _NumericField {
  final String column;
  final String label;
  final String? hint;

  /// Whether blank is a valid answer, meaning "upstream never reported this".
  final bool nullable;

  final String? Function(int value) rangeCheck;

  const _NumericField(
    this.column,
    this.label, {
    required this.rangeCheck,
    this.hint,
    this.nullable = false,
  });

  String? errorFor(String text) {
    if (text.isEmpty) return nullable ? null : '$label is required';
    final parsed = int.tryParse(text);
    if (parsed == null) return 'Enter a whole number';
    return rangeCheck(parsed);
  }
}

/// Range check shared by Kills and Damage, using the same ceiling
/// `withPlausibleStats` applies to synced matches - without it, a typo here
/// sets the edited flag and blocks any later sync from correcting it.
String? _inRange(String label, int value, int max) {
  if (value < 0) return "$label can't be negative";
  if (value > max) return '$label seems too high';
  return null;
}

String? _rpChangeRange(int value) {
  if (value < kMinEditableRpChange) return "RP change seems too low";
  if (value > kMaxEditableRpChange) return "RP change seems too high";
  return null;
}

const _numericFields = [
  _NumericField(
    'kills',
    'Kills',
    hint: 'Blank if unknown',
    nullable: true,
    rangeCheck: _killsRange,
  ),
  _NumericField(
    'damage',
    'Damage',
    hint: 'Blank if unknown',
    nullable: true,
    rangeCheck: _damageRange,
  ),
  _NumericField('rp_change', 'RP change', rangeCheck: _rpChangeRange),
];

String? _killsRange(int value) => _inRange('Kills', value, kMaxPlausibleKills);
String? _damageRange(int value) =>
    _inRange('Damage', value, kMaxPlausibleDamage);

/// Correction form for a single match: kills, damage, RP change, and legend.
///
/// A blank Kills/Damage field saves as NULL, which reads as "not reported" and
/// drops the match out of that stat's averages instead of counting it as zero.
/// Legend is picked from a fixed list rather than typed, so a correction can't
/// introduce a name that never appears anywhere else in the breakdown.
class MatchEditSheet extends ConsumerStatefulWidget {
  final RankedMatch match;

  const MatchEditSheet({super.key, required this.match});

  @override
  ConsumerState<MatchEditSheet> createState() => _MatchEditSheetState();
}

class _MatchEditSheetState extends ConsumerState<MatchEditSheet> {
  late final Map<String, TextEditingController> _controllers;
  late final Set<String> _edited;
  late final List<String> _legendOptions;
  late String _legend;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _edited = {...widget.match.editedFields};
    _controllers = {
      for (final f in _numericFields)
        f.column: TextEditingController(text: _initialText(f.column)),
    };
    _legend = widget.match.legend;
    final names = [for (final l in kLegends) l.name]..sort();
    // The stored legend may be a name outside the current roster (e.g. the raw
    // 'Unknown' fallback for a malformed API row) — keep it selectable rather
    // than silently swapping the dropdown to some other legend.
    _legendOptions = names.contains(_legend) ? names : [_legend, ...names];
  }

  String _initialText(String column) {
    final m = widget.match;
    return switch (column) {
      'kills' => m.kills?.toString() ?? '',
      'damage' => m.damage?.toString() ?? '',
      'rp_change' => m.rpChange.toString(),
      _ => '',
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The columns whose form value differs from what the match holds, or null
  /// when a field is filled in a way that can't be saved.
  Map<String, Object?>? _changes() {
    final out = <String, Object?>{};

    for (final f in _numericFields) {
      final text = _controllers[f.column]!.text.trim();
      if (text == _initialText(f.column)) continue;
      if (f.errorFor(text) != null) return null;
      out[f.column] = text.isEmpty ? null : int.parse(text);
    }

    if (_legend != widget.match.legend) out['legend'] = _legend;

    return out;
  }

  Future<void> _save() async {
    if (_saving) return;
    final changes = _changes();
    if (changes == null) {
      setState(() => _error = 'Check the highlighted values and try again.');
      return;
    }
    if (changes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref
          .read(rankedHistoryStoreProvider)
          .editMatch(widget.match.dedupKey, changes);
      if (!saved) {
        // No row matched this match's id - report the failure instead of
        // applying the edit to the in-memory copy the caller would otherwise
        // treat as persisted.
        if (mounted) {
          setState(() {
            _error = 'That match is no longer in your history.';
            _saving = false;
          });
        }
        return;
      }
      _refreshBreakdown();
      if (mounted) Navigator.pop(context, widget.match.withEdits(changes));
    } catch (e, st) {
      log.w('Match edit failed', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _error = 'Could not save the correction.';
          _saving = false;
        });
      }
    }
  }

  Future<void> _resetAll() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(rankedHistoryStoreProvider)
          .clearEdits(widget.match.dedupKey);
      _refreshBreakdown();
      if (mounted) Navigator.pop(context, widget.match.withEditsCleared());
    } catch (e, st) {
      log.w('Match edit reset failed', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _error = 'Could not clear the corrections.';
          _saving = false;
        });
      }
    }
  }

  /// Rebuilds every view fed by stored match rows. The sync provider is left
  /// alone, so saving an edit never spends a `/games` request.
  void _refreshBreakdown() => invalidateMatchDerivedProviders(ref);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Correct this match',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppTheme.xs),
              const Text(
                'Corrected values are kept when new match data arrives.',
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
              const SizedBox(height: AppTheme.md),
              _LegendRow(
                options: _legendOptions,
                value: _legend,
                edited: _edited.contains('legend'),
                onChanged: (v) => setState(() => _legend = v),
              ),
              const SizedBox(height: AppTheme.sm),
              for (final f in _numericFields) ...[
                _NumericFieldRow(
                  field: f,
                  controller: _controllers[f.column]!,
                  edited: _edited.contains(f.column),
                ),
                const SizedBox(height: AppTheme.sm),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppTheme.xs),
                Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.red, fontSize: 13),
                ),
              ],
              const SizedBox(height: AppTheme.md),
              Row(
                children: [
                  if (_edited.isNotEmpty)
                    TextButton(
                      onPressed: _saving ? null : _resetAll,
                      child: const Text(
                        'Reset to synced',
                        style: TextStyle(color: AppTheme.muted),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  ),
                  const SizedBox(width: AppTheme.sm),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared label column width so the legend dropdown and numeric fields line up.
const _kLabelWidth = 130.0;

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool edited;

  const _FieldLabel({required this.label, required this.edited});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kLabelWidth,
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          ),
          if (edited) ...[
            const SizedBox(width: 4),
            const Icon(Icons.edit, size: 12, color: AppTheme.accent),
          ],
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final List<String> options;
  final String value;
  final bool edited;
  final ValueChanged<String> onChanged;

  const _LegendRow({
    required this.options,
    required this.value,
    required this.edited,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FieldLabel(label: 'Legend', edited: edited),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            dropdownColor: AppTheme.surface,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final name in options)
                DropdownMenuItem(value: name, child: Text(name)),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

class _NumericFieldRow extends StatefulWidget {
  final _NumericField field;
  final TextEditingController controller;
  final bool edited;

  const _NumericFieldRow({
    required this.field,
    required this.controller,
    required this.edited,
  });

  @override
  State<_NumericFieldRow> createState() => _NumericFieldRowState();
}

class _NumericFieldRowState extends State<_NumericFieldRow> {
  @override
  void initState() {
    super.initState();
    // Re-render on every keystroke so the range error updates live rather than
    // only at save time.
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.field.errorFor(widget.controller.text.trim());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _FieldLabel(label: widget.field.label, edited: widget.edited),
        Expanded(
          child: TextField(
            controller: widget.controller,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[-0-9]')),
            ],
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.field.hint,
              hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
              errorText: error,
              errorStyle: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}
