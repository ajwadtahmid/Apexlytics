import 'package:flutter/material.dart';
import '../../constants/api_constants.dart';
import '../../providers/refresh_all_provider.dart';
import '../../utils/theme.dart';

/// Per-profile results of "Refresh all"; opened only when something needs a look.
Future<void> showRefreshAllSheet(
  BuildContext context,
  RefreshAllReport report,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (_) => _RefreshAllSheet(report: report),
  );
}

class _RefreshAllSheet extends StatelessWidget {
  final RefreshAllReport report;
  const _RefreshAllSheet({required this.report});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Refresh all',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTheme.xs),
            Text(
              report.newMatches > 0
                  ? '+${report.newMatches} new matches across '
                        '${report.results.length} profiles'
                  : '${report.results.length} profiles checked',
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
            const SizedBox(height: AppTheme.md),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final result in report.results)
                      _ResultTile(result: result),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final ProfileRefreshResult result;
  const _ResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final ok = !result.hasProblem;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.sm),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.md),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ok ? Icons.check_circle : Icons.error_outline,
              color: ok ? AppTheme.green : AppTheme.orange,
              size: 20,
            ),
            const SizedBox(width: AppTheme.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${result.profile.name} · '
                    '${ApiConstants.labelFor(result.profile.platform)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.historySummary,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                  Text(
                    result.statsSummary,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
