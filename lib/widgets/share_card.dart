import 'package:flutter/material.dart';
import '../utils/app_logger.dart';
import '../utils/notifications.dart';
import '../utils/share_image.dart';
import '../utils/theme.dart';
import 'legend_asset_image.dart' show legendImageKey;

/// The logical width every shareable card is laid out at. At a pixel ratio of
/// 3 the shared image is 1080 px wide.
const double kShareCardWidth = 360;

/// The standard card height: 4:5, which suits Instagram, Discord and X. A card
/// with more to say can ask for more.
const double kShareCardHeight = 450;

/// The frame around a shareable card's [child]: who it is for and what it
/// shows on top, an optional faded legend portrait behind, and the Apexlytics
/// mark at the bottom right, on a dark gradient.
///
/// With a [name] it leads, in white and large, and [label] sits under it small
/// and muted. Without one (the player hid it) [label] leads instead. [child]
/// fills the space between that header and the mark.
class ShareCardFrame extends StatelessWidget {
  final String label;
  final String? name;

  /// A legend whose portrait is faded in on the right. Null for none.
  final String? legend;
  final double height;
  final Widget child;
  const ShareCardFrame({
    super.key,
    required this.label,
    this.name,
    this.legend,
    this.height = kShareCardHeight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final who = name;
    final art = legend;
    return Container(
      width: kShareCardWidth,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.surface2, AppTheme.bg],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.accent.withAlpha(90)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (art != null)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 250,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.transparent, Colors.white.withAlpha(150)],
                  stops: const [0, 0.65],
                ).createShader(rect),
                child: Image.asset(
                  'assets/legends/${legendImageKey(art)}.webp',
                  fit: BoxFit.cover,
                  alignment: const Alignment(0.2, -1),
                  cacheWidth: 750,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppTheme.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (who != null) ...[
                  Text(
                    who,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(label, style: AppTheme.caption),
                ] else
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: AppTheme.md),
                Expanded(child: child),
                const SizedBox(height: AppTheme.sm),
                const Align(alignment: Alignment.centerRight, child: _Brand()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Apexlytics mark at the bottom right of a card: the app icon and its name.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Image.asset(
            'assets/logos/logo.png',
            width: 22,
            height: 22,
            cacheWidth: 66,
            errorBuilder: (_, _, _) => const SizedBox(width: 22, height: 22),
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'APEXLYTICS',
          style: TextStyle(
            color: AppTheme.accent,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

/// One figure on a card, in a rounded tile with an icon: a small muted label
/// over the value. Two fit across a card.
class ShareTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  const ShareTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  /// Two tiles side by side across the card's padding and its 1 px border, with
  /// a gap between. A pixel of slack keeps them from wrapping on rounding.
  static const double width =
      (kShareCardWidth - 2 - 2 * AppTheme.lg - AppTheme.sm - 1) / 2;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.sm + 2,
        vertical: AppTheme.sm,
      ),
      decoration: BoxDecoration(
        color: AppTheme.bg.withAlpha(190),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.surface2),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.accent),
          const SizedBox(width: AppTheme.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.captionSmall,
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color ?? AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Previews a shareable card on screen and shares it as an image. [cardBuilder]
/// gets whether the player's name should appear; the choice is off for nobody
/// by default, and a card never carries a UID.
class ShareCardScreen extends StatefulWidget {
  final String title;
  final Widget Function(bool showName) cardBuilder;

  /// Offered when the card can carry the player's name.
  final bool offerNameToggle;

  /// A test seam in place of the system share sheet.
  final Future<bool> Function(GlobalKey key)? onShare;

  /// A test seam in place of the save dialog, used where the platform can't
  /// share a file. Resolves to the path saved to, or null when cancelled.
  final Future<String?> Function(GlobalKey key)? onSave;

  const ShareCardScreen({
    super.key,
    required this.title,
    required this.cardBuilder,
    this.offerNameToggle = true,
    this.onShare,
    this.onSave,
  });

  @override
  State<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends State<ShareCardScreen> {
  final _boundary = GlobalKey();
  bool _showName = true;
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await (widget.onShare ?? shareBoundary)(_boundary);
    } catch (e, st) {
      log.w('Sharing the card failed', error: e, stackTrace: st);
      if (mounted) context.showMessage("Couldn't share the card.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Where sharing a file isn't possible: asks where to keep the image instead.
  Future<void> _save() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final path = await (widget.onSave ?? saveBoundary)(_boundary);
      if (path != null && mounted) context.showMessage('Saved to $path');
    } catch (e, st) {
      log.w('Saving the card failed', error: e, stackTrace: st);
      if (mounted) context.showMessage("Couldn't save the card.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canShare = canShareFiles;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            // Scaled down on a narrow screen; the shared image is the card at
            // its own size either way.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: RepaintBoundary(
                key: _boundary,
                // The card looks the same whatever text size the phone uses.
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.noScaling),
                  child: widget.cardBuilder(_showName),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.md),
            if (widget.offerNameToggle)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show my name'),
                subtitle: const Text(
                  'Your player ID is never included.',
                  style: AppTheme.caption,
                ),
                value: _showName,
                onChanged: (v) => setState(() => _showName = v),
              ),
            FilledButton.icon(
              onPressed: _sharing ? null : (canShare ? _share : _save),
              icon: Icon(canShare ? Icons.ios_share : Icons.save_alt, size: 18),
              label: Text(canShare ? 'Share' : 'Save image'),
            ),
          ],
        ),
      ),
    );
  }
}
