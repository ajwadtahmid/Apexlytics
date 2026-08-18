import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../utils/theme.dart';

Future<void> _openProfileSearch() async {
  await launchUrl(
    Uri.parse('https://apexlegendsstatus.com/profile/search/'),
    mode: LaunchMode.externalApplication,
  );
}

Future<void> _openFullGuide() async {
  await launchUrl(
    Uri.parse(
      'https://github.com/ajwadtahmid/Apexlytics#ranked-breakdown-guide',
    ),
    mode: LaunchMode.externalApplication,
  );
}

/// "How ranked tracking works" — explains the mechanics behind the empty
/// states in RankedBreakdownView so a confused user has somewhere to look
/// beyond the inline copy.
void showRankedInfoSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppTheme.md,
          AppTheme.md,
          AppTheme.md,
          AppTheme.lg,
        ),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.muted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.md),
          const Text(
            'How Ranked Tracking Works',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppTheme.lg),
          ..._section('Why it starts empty', [
            'Match history is only recorded while you\'re actively playing '
                'ranked with Apexlytics (or a browser tab of your profile on '
                'apexlegendsstatus.com) is open for that account. A brand '
                'new profile has nothing recorded yet, so the breakdown '
                'starts blank.',
          ]),
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.sm),
            child: InkWell(
              onTap: _openProfileSearch,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: const Text(
                'Find your profile →',
                style: TextStyle(fontSize: 13, color: AppTheme.accent),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.md),
          ..._section('"Server busy"', [
            'We\'re currently limited by our API\'s request budget. Nothing is '
                'lost — you\'ll see your data soon.',
          ]),
          const SizedBox(height: AppTheme.md),
          ..._section('History is forward-only', [
            'Once tracking starts, only matches played from that point on can '
                'be recorded. Matches played before tracking started can\'t be '
                'recovered.',
          ]),
          const SizedBox(height: AppTheme.lg),
          Center(
            child: InkWell(
              onTap: _openFullGuide,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: const Text(
                'Full guide on GitHub →',
                style: TextStyle(fontSize: 13, color: AppTheme.accent),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

List<Widget> _section(String title, List<String> paragraphs) {
  return [
    Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: AppTheme.sm),
    Container(
      padding: const EdgeInsets.all(AppTheme.md),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in paragraphs)
            Text(
              p,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary,
                height: 1.5,
              ),
            ),
        ],
      ),
    ),
  ];
}
