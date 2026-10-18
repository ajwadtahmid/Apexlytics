import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// One segment of [PillSegments].
class PillOption {
  final String label;

  /// What a screen reader says, when it should be more than [label].
  final String? semanticLabel;

  /// The icon to the left of the label, drawn in the colour it is given.
  final Widget Function(Color color) icon;

  /// A small lock after the label: the option is on and cannot be changed.
  final bool locked;

  const PillOption({
    required this.label,
    required this.icon,
    this.semanticLabel,
    this.locked = false,
  });
}

/// A choice between a few options as one rounded capsule, shared equally, the
/// selected one filled orange. The look of the Home mode picker, for a smaller
/// choice inside a card.
class PillSegments extends StatelessWidget {
  final List<PillOption> options;
  final int selected;
  final ValueChanged<int> onChanged;

  /// A smaller capsule, only as wide as its options need, for a choice that
  /// should sit quietly beside the main one. Otherwise the options share the
  /// full width.
  final bool compact;

  const PillSegments({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 3 : AppTheme.xs),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          for (final (i, option) in options.indexed)
            () {
              final segment = _Segment(
                option: option,
                selected: i == selected,
                compact: compact,
                onTap: () => onChanged(i),
              );
              // Flexible when compact, so large text shrinks a segment.
              return compact
                  ? Flexible(child: segment)
                  : Expanded(child: segment);
            }(),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final PillOption option;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  const _Segment({
    required this.option,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppTheme.muted;
    final radius = BorderRadius.circular(AppTheme.radiusFull);
    return Semantics(
      button: true,
      selected: selected,
      label: option.semanticLabel ?? option.label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: AppTheme.chipAnimation,
          padding: EdgeInsets.symmetric(
            vertical: compact ? 5 : 10,
            horizontal: compact ? 14 : 6,
          ),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : Colors.transparent,
            borderRadius: radius,
          ),
          // Scales down, so large text shrinks a segment instead of overflowing it.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                option.icon(color),
                const SizedBox(width: 5),
                Text(
                  option.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: compact ? 12 : 13,
                  ),
                ),
                if (option.locked) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.lock_outline, size: 11, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
