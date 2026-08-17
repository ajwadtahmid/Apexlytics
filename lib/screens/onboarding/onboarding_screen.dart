import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../utils/theme.dart';

/// A single orientation slide.
class _OnboardingPage {
  final IconData icon;
  final String title;
  final String body;

  /// Optional small print shown under the body (e.g. the not-affiliated note).
  final String? footnote;

  /// Optional short callout for an actionable tip (e.g. equip trackers).
  final String? tip;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
    this.footnote,
    this.tip,
  });
}

const _pages = <_OnboardingPage>[
  _OnboardingPage(
    icon: Icons.insights,
    title: 'Welcome to Apexlytics',
    body:
        'Your companion for Apex Legends — track your stats, follow the map '
        'rotation, and dig into your performance.',
    footnote:
        'Unofficial companion app. Not made by, affiliated with, or endorsed '
        'by Electronic Arts or Respawn Entertainment.',
  ),
  _OnboardingPage(
    icon: Icons.bar_chart,
    title: 'See your progress',
    body:
        'Add your player profile to track your legends, weapons, and career '
        'stats. Save up to 5 profiles and switch between them anytime.',
    tip:
        'Tip: equip the Apex Kills and Apex Damage trackers for legends you '
        'play. Stats only update for trackers that are equipped.',
  ),
  _OnboardingPage(
    icon: Icons.map_outlined,
    title: "Know where you're dropping",
    body:
        'The Home tab shows live map rotations for Ranked, Pubs, Wildcard, and '
        'Mixtape — plus news, server status, and the Predator cutoff. Turn on '
        'notifications to get a heads-up before maps change.',
  ),
  _OnboardingPage(
    icon: Icons.search,
    title: 'Scout friends and rivals',
    body:
        'Search any player by name, compare stats side by side, and save '
        'favorites for quick access.',
  ),
  _OnboardingPage(
    icon: Icons.leaderboard_outlined,
    title: 'Record your ranked history',
    body:
        'The Ranked tab breaks down every match — RP over time, your best '
        'legends and maps, and how you play by time of day. Open it and tap '
        'Start recording to begin.',
    tip:
        'Matches are only recorded while Apexlytics is open and in the '
        'foreground, so turn on "Keep screen on" while you play.',
    footnote:
        'Recording starts from the moment you turn it on — matches played '
        'before that cannot be recovered.',
  ),
];

/// Full-screen orientation tour. Purely presentational — [onDone] owns marking
/// the tour seen, dismissing, and any post-tour navigation, so the same screen
/// serves both first-run and the replay-from-Settings flow.
class OnboardingScreen extends StatefulWidget {
  final Future<void> Function() onDone;

  const OnboardingScreen({super.key, required this.onDone});

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
                        onPressed: _isFirstPage ? null : _back,
                        icon: const Icon(Icons.arrow_back, color: AppTheme.muted),
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
                  child: Text(_isLastPage ? 'Get started' : 'Next'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.xl),
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
            child: Icon(page.icon, size: 44, color: AppTheme.accent),
          ),
          const SizedBox(height: AppTheme.xl),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppTheme.md),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          if (page.tip != null) ...[
            const SizedBox(height: AppTheme.lg),
            Container(
              padding: const EdgeInsets.all(AppTheme.sm),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Text(
                page.tip!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.accent2,
                  fontSize: 12.5,
                  height: 1.4,
                ),
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
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  final int count;
  final int active;

  const _DotsIndicator({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}
