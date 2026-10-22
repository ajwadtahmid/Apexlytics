import 'package:flutter/material.dart';

import '../utils/theme.dart';
import 'sheet_handle.dart';

/// One row of a [showChoiceSheet]: an icon and a name.
class ChoiceOption<T> {
  final T value;
  final IconData icon;
  final String label;
  const ChoiceOption({
    required this.value,
    required this.icon,
    required this.label,
  });
}

/// A bottom sheet that picks one of [options], laid out like the Legends tab's
/// sort sheet: a handle, a [title], then a tile for each choice, the one in use
/// ([selected]) lit in the accent colour with a tick.
/// Choosing calls [onChosen] and closes it. A [footnote], when given, goes
/// under the list.
Future<void> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<ChoiceOption<T>> options,
  required T selected,
  required ValueChanged<T> onChosen,
  String? footnote,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.md,
          AppTheme.md,
          AppTheme.md,
          AppTheme.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: AppTheme.md),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTheme.sm),
            for (final option in options)
              _ChoiceTile<T>(
                option: option,
                selected: option.value == selected,
                onTap: () {
                  onChosen(option.value);
                  Navigator.of(sheetContext).pop();
                },
              ),
            if (footnote != null) ...[
              const SizedBox(height: AppTheme.sm),
              Text(footnote, style: AppTheme.captionSmall),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ChoiceTile<T> extends StatelessWidget {
  final ChoiceOption<T> option;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.accent : AppTheme.textPrimary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(option.icon, size: 20, color: color),
      title: Text(
        option.label,
        style: TextStyle(
          color: color,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, size: 18, color: AppTheme.accent)
          : null,
      onTap: onTap,
    );
  }
}
