import 'package:flutter/material.dart';
import '../utils/theme.dart';
import 'surface_card.dart';

/// The app's one error/message widget, in three layouts chosen by [compact] /
/// [fullScreen] (mutually exclusive; default is "inline"):
///
/// - `compact: true` → tile row (icon + title/subtitle + Retry) for a tight
///   space, e.g. a Home summary tile.
/// - `fullScreen: true` → centered whole-screen state with optional title,
///   extra content, and up to three actions, e.g. My Stats/Search fetch
///   failures or Ranked Breakdown's "still waiting for data" states.
/// - default → inline block in a [SurfaceCard], e.g. Home's map-rotation card.
///
/// Replaces three widgets that used to drift out of sync (missing a Retry
/// button here, an action there) — one parameterized widget means a fix
/// applies everywhere at once.
class ErrorCard extends StatelessWidget {
  /// Per-layout default when unset: outlined (compact), rounded (inline),
  /// error_outline (fullScreen).
  final IconData? icon;

  /// Defaults to orange (compact/inline) or muted (fullScreen) when unset.
  final Color? iconColor;

  /// Defaults to 22/32/40 for compact/inline/fullScreen when unset.
  final double? iconSize;

  /// Bold heading above [message]. [fullScreen] only.
  final String? title;

  final String message;

  final bool compact;
  final bool fullScreen;

  /// Retry [TextButton], shown when set. Optional everywhere — a [fullScreen]
  /// state that navigates away instead (e.g. "Back") can omit this.
  final VoidCallback? onRetry;
  final String retryLabel;

  /// Optional promoted action, rendered as a filled button above Retry.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Optional extra content below the message. [fullScreen] only.
  final Widget? extra;

  /// Optional secondary action, rendered as an outlined button above the
  /// promoted action. [fullScreen] only.
  final String? secondaryActionLabel;
  final IconData? secondaryActionIcon;
  final VoidCallback? onSecondaryAction;

  /// Optional trailing text link. [fullScreen] only.
  final VoidCallback? onLearnMore;
  final String learnMoreLabel;

  const ErrorCard({
    super.key,
    this.icon,
    this.iconColor,
    this.iconSize,
    this.title,
    required this.message,
    this.compact = false,
    this.fullScreen = false,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.actionLabel,
    this.onAction,
    this.extra,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.onSecondaryAction,
    this.onLearnMore,
    this.learnMoreLabel = 'How does this work?',
  }) : assert(
         !(compact && fullScreen),
         'compact and fullScreen are mutually exclusive',
       );

  IconData get _resolvedIcon =>
      icon ??
      (compact
          ? Icons.warning_amber_outlined
          : fullScreen
          ? Icons.error_outline
          : Icons.warning_amber_rounded);

  Color get _resolvedIconColor =>
      iconColor ?? (fullScreen ? AppTheme.muted : AppTheme.orange);

  double get _resolvedIconSize =>
      iconSize ??
      (compact
          ? 22
          : fullScreen
          ? 40
          : 32);

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompact();
    if (fullScreen) return _buildFullScreen();
    return _buildInline();
  }

  Widget _buildCompact() {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.md,
          vertical: AppTheme.summaryTileVerticalPadding,
        ),
        child: Row(
          children: [
            Icon(
              _resolvedIcon,
              color: _resolvedIconColor,
              size: _resolvedIconSize,
            ),
            const SizedBox(width: AppTheme.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const Text(
                    'Failed to load',
                    style: TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: Text(
                  retryLabel,
                  style: const TextStyle(color: AppTheme.accent, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInline() {
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        children: [
          Icon(
            _resolvedIcon,
            color: _resolvedIconColor,
            size: _resolvedIconSize,
          ),
          const SizedBox(height: AppTheme.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(
                retryLabel,
                style: const TextStyle(color: AppTheme.accent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFullScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _resolvedIcon,
              color: _resolvedIconColor,
              size: _resolvedIconSize,
            ),
            const SizedBox(height: AppTheme.md),
            if (title != null) ...[
              Text(
                title!,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppTheme.xs),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            ?extra,
            const SizedBox(height: AppTheme.md),
            if (onSecondaryAction != null) ...[
              OutlinedButton.icon(
                onPressed: onSecondaryAction,
                icon: Icon(secondaryActionIcon ?? Icons.bar_chart, size: 16),
                label: Text(secondaryActionLabel ?? ''),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: const BorderSide(color: AppTheme.accent),
                ),
              ),
              const SizedBox(height: AppTheme.xs),
            ],
            if (actionLabel != null && onAction != null) ...[
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                child: Text(actionLabel!),
              ),
              const SizedBox(height: AppTheme.xs),
            ],
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: Text(
                  retryLabel,
                  style: const TextStyle(color: AppTheme.accent),
                ),
              ),
            if (onLearnMore != null)
              TextButton(
                onPressed: onLearnMore,
                child: Text(
                  learnMoreLabel,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
