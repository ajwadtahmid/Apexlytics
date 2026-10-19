import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../providers/navigation_provider.dart' show AppTab;
import '../../providers/settings_provider.dart' show PlayerSettingsNotifier;
import '../../utils/theme.dart';

/// One point on a slide: an icon, an optional bold [label] (a tile or tab name
/// as the app shows it) and the line that goes with it.
class _Point {
  final IconData icon;
  final String? label;
  final String text;

  const _Point(this.text, {this.label, this.icon = Icons.check});
}

/// A single orientation slide.
class _OnboardingPage {
  /// The tab the slide is about: its icon fronts the slide and its name sits
  /// above the title, so a slide matches the nav bar. Null for a general one.
  final AppTab? tab;

  /// Where in the tab, shown after its name ("Overview").
  final String? section;

  /// The icon when there is no [tab].
  final IconData? icon;
  final String title;

  /// A line or two of introduction.
  final String? body;

  /// Short points under the body, one idea each.
  final List<_Point> points;

  /// A line that closes the slide, under the points.
  final String? closing;

  /// Optional small print shown under the body (e.g. the not-affiliated note).
  final String? footnote;

  const _OnboardingPage({
    this.tab,
    this.section,
    this.icon,
    required this.title,
    this.body,
    this.points = const [],
    this.closing,
    this.footnote,
  });

  IconData get displayIcon => tab?.activeIcon ?? icon ?? Icons.insights;

  /// "STATS TAB" or "STATS TAB · OVERVIEW"; null for a slide with no tab.
  String? get tabLabel => tab == null
      ? null
      : '${tab!.label} tab${section == null ? '' : ' · $section'}'
            .toUpperCase();
}

const _pages = <_OnboardingPage>[
  _OnboardingPage(
    icon: Icons.insights,
    title: 'Welcome to Apexlytics',
    body:
        'Your companion for Apex Legends. Track your stats, follow the map '
        'rotation, and dig into your performance.',
    footnote:
        'Unofficial companion app. Not made by, affiliated with, or endorsed '
        'by Electronic Arts or Respawn Entertainment.',
  ),
  _OnboardingPage(
    tab: AppTab.home,
    title: "Know where you're dropping",
    body:
        'Live map rotations for Ranked, Pubs, Wildcards and Mixtape, with a '
        'countdown to the next map.',
    points: [
      _Point('Tap the bell on the map to get an alert before it changes'),
      _Point(
        'See the Pred cutoff for your platform, plus news and server status',
      ),
    ],
  ),
  _OnboardingPage(
    tab: AppTab.stats,
    title: 'Set up your player',
    body:
        'Open the Stats tab and add your player by name or UID (Nintendo '
        'Switch needs a UID). Save up to '
        '${PlayerSettingsNotifier.maxProfileCount} profiles and switch '
        'between them anytime.',
    points: [
      _Point(
        'Equip Apex Kills and Apex Damage on the legends you play. Stats '
        'only update for equipped trackers.',
        label: 'Equip your trackers',
        icon: Icons.tune,
      ),
      _Point(
        'A chart of every ranked game, across the split or a single night',
        label: 'Then watch your RP climb',
        icon: Icons.show_chart,
      ),
    ],
    closing: 'It starts empty and fills in as you play ranked.',
  ),
  _OnboardingPage(
    icon: Icons.history,
    title: 'How recording works',
    points: [
      _Point(
        'Games are saved only while your profile is tracked: keep Apexlytics '
        'open (turn on "Keep screen on" in Settings), or keep your profile '
        'open on apexlegendsstatus.com.',
      ),
      _Point("Games played before tracking started can't be recovered."),
      _Point(
        'Your history lives only on this device. Export a backup in Settings '
        'under Data, and Apexlytics will remind you.',
      ),
    ],
  ),
  _OnboardingPage(
    tab: AppTab.stats,
    section: 'Overview',
    title: 'Your ranked history',
    body:
        'Once games are recorded, tiles under the RP chart open the tools that '
        'answer your questions.',
    points: [
      _Point(
        'Which legends and maps earn me RP?',
        label: 'Legend × Map, Pick Rate',
        icon: Icons.grid_view_rounded,
      ),
      _Point(
        'When do I play best?',
        label: 'Performance Trends',
        icon: Icons.schedule,
      ),
      _Point('How did each night go?', label: 'Sessions', icon: Icons.timeline),
      _Point(
        'How does this split stack up against another?',
        label: 'Compare',
        icon: Icons.compare_arrows,
      ),
      _Point(
        'What can I share, and what is my best?',
        label: 'Recap, Records',
        icon: Icons.auto_awesome_outlined,
      ),
    ],
  ),
  _OnboardingPage(
    tab: AppTab.stats,
    title: 'The four tabs, one split',
    body: 'Pick a split and week at the top, and everything follows it.',
    points: [
      _Point(
        'The big picture, and the tools above',
        label: 'Overview',
        icon: Icons.dashboard_outlined,
      ),
      _Point(
        "Each legend's results; tap one to see its games",
        label: 'Legends',
        icon: Icons.person_outline,
      ),
      _Point('The same for each map', label: 'Maps', icon: Icons.map_outlined),
      _Point(
        'Every game, pubs included; tap one to see or correct it',
        label: 'Games',
        icon: Icons.format_list_bulleted,
      ),
    ],
  ),
  _OnboardingPage(
    tab: AppTab.search,
    title: 'Scout friends and rivals',
    body: 'Look up any player by name or UID.',
    points: [
      _Point('Compare stats side by side'),
      _Point(
        'Star a player to keep them as a favorite, and swipe one away to '
        'remove it',
      ),
    ],
  ),
  _OnboardingPage(
    tab: AppTab.settings,
    title: 'Make it yours',
    body: 'Everything else is in Settings.',
    points: [
      _Point('Choose which tab opens first and how often stats refresh'),
      _Point('Set up map alerts, and send yourself a test'),
      _Point('Export and import a backup of your history'),
      _Point('Report a bug with the details filled in for you'),
    ],
  ),
];

/// Full-screen orientation tour. Purely presentational — [onDone] owns marking
/// the tour seen, dismissing, and any post-tour navigation, so the same screen
/// serves both first-run and the replay-from-Settings flow.
class OnboardingScreen extends StatefulWidget {
  final Future<void> Function() onDone;

  /// What the button on the last slide says, for what comes next.
  final String finishLabel;

  const OnboardingScreen({
    super.key,
    required this.onDone,
    this.finishLabel = 'Get started',
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  // Guards against a double-tap firing onDone twice while the route pops.
  bool _finishing = false;

  bool get _isLastPage => _page == _pages.length - 1;
  bool get _isFirstPage => _page == 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    _controller.nextPage(
      duration: AppTheme.shortAnimation,
      curve: Curves.easeOut,
    );
  }

  void _back() {
    _controller.previousPage(
      duration: AppTheme.shortAnimation,
      curve: Curves.easeOut,
    );
  }

  void _finish() {
    if (_finishing) return;
    _finishing = true;
    unawaited(widget.onDone());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Fixed height so the pager doesn't jump as Back/Skip fade in/out.
            SizedBox(
              height: 48,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedOpacity(
                      opacity: _isFirstPage ? 0 : 1,
                      duration: AppTheme.shortAnimation,
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: _isFirstPage ? null : _back,
                        icon: const Icon(
                          Icons.arrow_back,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                  ),
                  // Skip stays out on the last page, where the primary button
                  // already dismisses.
                  Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedOpacity(
                      opacity: _isLastPage ? 0 : 1,
                      duration: AppTheme.shortAnimation,
                      child: TextButton(
                        onPressed: _isLastPage ? null : _finish,
                        child: const Text(
                          'Skip',
                          style: TextStyle(color: AppTheme.muted, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _OnboardingPageContent(page: _pages[i]),
              ),
            ),
            _DotsIndicator(count: _pages.length, active: _page),
            const SizedBox(height: AppTheme.lg),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.lg,
                0,
                AppTheme.lg,
                AppTheme.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLastPage ? _finish : _next,
                  child: Text(_isLastPage ? widget.finishLabel : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageContent extends StatelessWidget {
  final _OnboardingPage page;

  const _OnboardingPageContent({required this.page});

  @override
  Widget build(BuildContext context) {
    // Scrolls when the slide is taller than the space between the header and
    // the buttons (a small phone, larger text); still centred when it fits.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(page.displayIcon, size: 44, color: AppTheme.accent),
              ),
              const SizedBox(height: AppTheme.xl),
              if (page.tabLabel != null) ...[
                Text(
                  page.tabLabel!,
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: AppTheme.xs),
              ],
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (page.body != null) ...[
                const SizedBox(height: AppTheme.md),
                Text(
                  page.body!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
              if (page.points.isNotEmpty) ...[
                const SizedBox(height: AppTheme.lg),
                _Points(page.points),
              ],
              if (page.closing != null) ...[
                const SizedBox(height: AppTheme.md),
                Text(
                  page.closing!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ],
              if (page.footnote != null) ...[
                const SizedBox(height: AppTheme.lg),
                Text(
                  page.footnote!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The points of a slide, left aligned in a card: easier to scan than a
/// paragraph. A point with a label shows it in bold above its line.
class _Points extends StatelessWidget {
  final List<_Point> points;
  const _Points(this.points);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.md),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, point) in points.indexed) ...[
            if (i > 0) const SizedBox(height: AppTheme.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(point.icon, size: 18, color: AppTheme.accent),
                ),
                const SizedBox(width: AppTheme.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (point.label != null)
                        Text(
                          point.label!,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                        ),
                      Text(
                        point.text,
                        style: TextStyle(
                          color: point.label == null
                              ? AppTheme.textPrimary
                              : AppTheme.muted,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  final int count;
  final int active;

  const _DotsIndicator({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${active + 1} of $count',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: AppTheme.shortAnimation,
              margin: const EdgeInsets.symmetric(horizontal: AppTheme.xs),
              width: i == active ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == active ? AppTheme.accent : AppTheme.surface2,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
            ),
        ],
      ),
    );
  }
}
