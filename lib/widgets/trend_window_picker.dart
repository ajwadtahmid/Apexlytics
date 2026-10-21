import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/stat_icons.dart';
import '../providers/entity_trend_overrides_provider.dart';
import '../providers/entity_trend_window_provider.dart';
import '../utils/formatting/format.dart' show formatNumber;
import '../utils/ranked/entity_trend_window.dart';
import '../utils/theme.dart';
import 'choice_sheet.dart';
import 'control_pill.dart';

/// Stands for "follow the window chosen for everything" in the sheet that gives
/// one legend or map its own.
const int _kFollowDefault = -1;

/// Stands for "a number I type" in both sheets.
const int _kCustom = -2;

/// Whether [choice] is one the sheets list by name (Auto or a shortcut), rather
/// than a count typed in.
bool _isListed(int choice) =>
    choice == kEntityTrendAuto || kEntityTrendPresets.contains(choice);

/// The sheets' row for a count typed in: "Custom…", or the count once one has
/// been, so it can be seen and lit.
ChoiceOption<int> _customOption(int choice) => ChoiceOption(
  value: _kCustom,
  icon: Icons.edit_outlined,
  label: _isListed(choice)
      ? 'Custom…'
      : 'Custom (${formatNumber(choice)} games)',
);

/// Asks for a count once the sheet that chose "Custom" has closed, and passes
/// it to [onValue].
void _askForCount(
  BuildContext context, {
  required int max,
  required int initial,
  String? note,
  required ValueChanged<int> onValue,
}) {
  Future<void>.microtask(() async {
    if (!context.mounted) return;
    final games = await showDialog<int>(
      context: context,
      builder: (_) => _CustomWindowDialog(
        max: max,
        initial: _isListed(initial) ? null : initial,
        note: note,
      ),
    );
    if (games != null) onValue(games);
  });
}

/// "Trends: Auto": the window a legend's or map's trend lines compare its recent
/// games over (see [entityTrendWindowProvider]), with a tap to change it.
class TrendWindowPill extends ConsumerWidget {
  const TrendWindowPill({super.key});

  /// How the choice reads on the pill.
  static String labelOf(int choice) =>
      choice == kEntityTrendAuto ? 'Auto' : '${formatNumber(choice)} games';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ControlPill(
      prefix: 'Trends:',
      icon: Icons.trending_up,
      label: labelOf(ref.watch(entityTrendWindowProvider)),
      onTap: () => showTrendWindowSheet(context, ref),
    );
  }
}

/// The sheet that picks the window for everything: Auto, a shortcut, or a count
/// typed in. A choice applies at once and closes it.
Future<void> showTrendWindowSheet(BuildContext context, WidgetRef ref) {
  final chosen = ref.read(entityTrendWindowProvider);
  final notifier = ref.read(entityTrendWindowProvider.notifier);
  return showChoiceSheet<int>(
    context,
    title: 'Trend window',
    options: [
      const ChoiceOption(
        value: kEntityTrendAuto,
        icon: Icons.auto_awesome,
        label: 'Auto',
      ),
      for (final n in kEntityTrendPresets)
        ChoiceOption(value: n, icon: StatIcons.games, label: 'Last $n games'),
      _customOption(chosen),
    ],
    selected: _isListed(chosen) ? chosen : _kCustom,
    onChosen: (n) => n == _kCustom
        ? _askForCount(
            context,
            max: kTrendCustomMax,
            initial: chosen,
            onValue: notifier.set,
          )
        : notifier.set(n),
    footnote:
        'Trend lines compare recent games with the average. Auto uses about a '
        'quarter of a legend\'s or map\'s games, from $kAutoTrendMinGames to '
        '$kAutoTrendMaxGames. Each can have its own window on its page.',
  );
}

/// "Trend window: 18 games", on a legend's or map's sheet: the window its trend
/// lines use, lit in the accent colour when it differs from what everything
/// else uses. A tap opens the sheet that changes it for this legend or map
/// alone.
class EntityTrendWindowPill extends ConsumerWidget {
  /// What the window is filed under (see `legendTrendKey` and `mapTrendKey`).
  final String overrideKey;

  /// The legend's or map's name, for the sheet's title.
  final String name;

  /// How many games it has, which limits the window a player can type in.
  final int games;

  /// The window in use.
  final EntityTrendWindow window;
  const EntityTrendWindowPill({
    super.key,
    required this.overrideKey,
    required this.name,
    required this.games,
    required this.window,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lit when it differs from what everything else uses.
    final choice = ref.watch(entityTrendOverridesProvider)[overrideKey];
    final own =
        choice != null && choice != ref.watch(entityTrendWindowProvider);
    return ControlPill(
      prefix: 'Trend window:',
      icon: Icons.trending_up,
      color: own ? AppTheme.accent : null,
      label: '${formatNumber(window.recent)} games',
      onTap: () => _showSheet(context, ref),
    );
  }

  Future<void> _showSheet(BuildContext context, WidgetRef ref) {
    final overrides = ref.read(entityTrendOverridesProvider.notifier);
    final global = ref.read(entityTrendWindowProvider);
    final autoIsDefault = global == kEntityTrendAuto;
    final own = ref.read(entityTrendOverridesProvider)[overrideKey];
    final max = maxTrendWindow(games);
    // What the sheet shows as chosen: nothing of its own, or Auto where that is
    // already the default, is "Default".
    final selected = own == null || (autoIsDefault && own == kEntityTrendAuto)
        ? _kFollowDefault
        : (_isListed(own) ? own : _kCustom);
    return showChoiceSheet<int>(
      context,
      title: 'Trend window for $name',
      options: [
        ChoiceOption(
          value: _kFollowDefault,
          icon: Icons.restart_alt,
          label: 'Default (${TrendWindowPill.labelOf(global)})',
        ),
        // Auto in its own right, for when everything else is on a count. With
        // Auto as the default it would only repeat the first row.
        if (!autoIsDefault)
          const ChoiceOption(
            value: kEntityTrendAuto,
            icon: Icons.auto_awesome,
            label: 'Auto',
          ),
        for (final n in kEntityTrendPresets)
          ChoiceOption(value: n, icon: StatIcons.games, label: 'Last $n games'),
        _customOption(own ?? kEntityTrendAuto),
      ],
      selected: selected,
      onChosen: (n) {
        if (n == _kCustom) {
          _askForCount(
            context,
            max: max,
            initial: own ?? kEntityTrendAuto,
            note:
                '$name has ${formatNumber(games)} games, so up to '
                '${formatNumber(max)}.',
            onValue: (v) => overrides.set(overrideKey, v),
          );
        } else if (n == _kFollowDefault) {
          overrides.clear(overrideKey);
        } else {
          overrides.set(overrideKey, n);
        }
      },
      footnote: 'Others follow Trends on the Legends and Maps tabs.',
    );
  }
}

/// Asks how many games count as recent, from [kTrendCustomMin] to [max]. Pops
/// with the count; "Use" waits for one in range.
class _CustomWindowDialog extends StatefulWidget {
  final int max;
  final int? initial;

  /// A line saying why [max] is what it is.
  final String? note;
  const _CustomWindowDialog({required this.max, this.initial, this.note});

  @override
  State<_CustomWindowDialog> createState() => _CustomWindowDialogState();
}

class _CustomWindowDialogState extends State<_CustomWindowDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial?.toString() ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _value => int.tryParse(_controller.text);

  bool get _valid {
    final v = _value;
    return v != null && v >= kTrendCustomMin && v <= widget.max;
  }

  @override
  Widget build(BuildContext context) {
    final showError = _controller.text.isNotEmpty && !_valid;
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Custom trend window'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How many of the newest games count as recent: '
            '$kTrendCustomMin to ${formatNumber(widget.max)}.',
            style: AppTheme.caption,
          ),
          if (widget.note != null) ...[
            const SizedBox(height: 2),
            Text(widget.note!, style: AppTheme.caption),
          ],
          const SizedBox(height: AppTheme.sm),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              suffixText: 'games',
              errorText: showError
                  ? 'Enter $kTrendCustomMin to ${formatNumber(widget.max)}'
                  : null,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_valid) Navigator.pop(context, _value);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppTheme.muted)),
        ),
        TextButton(
          onPressed: _valid ? () => Navigator.pop(context, _value) : null,
          child: const Text('Use'),
        ),
      ],
    );
  }
}
