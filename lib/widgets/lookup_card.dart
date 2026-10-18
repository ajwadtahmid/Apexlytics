import 'package:flutter/material.dart';
import '../constants/api_constants.dart';
import '../utils/lookup_form_state.dart';
import '../utils/navigation_utils.dart';
import '../utils/theme.dart';
import 'pill_segments.dart';
import 'platform_picker.dart';
import 'surface_card.dart';
import 'uid_search_toggle.dart';

/// The player lookup, in one card: the field with the UID pill at its start, and
/// the platform pills under it. Used by Search, first-time setup and Add / Edit
/// Profile, all driven by a [LookupFormState].
///
/// A notice from the state, and an [error] from the caller, show under the card.
class LookupCard extends StatelessWidget {
  final LookupFormState state;

  /// Called when the keyboard's action key is pressed, and by the arrow in the
  /// field when [arrowSubmits].
  final VoidCallback onSubmit;

  /// Whether the field has an arrow at its end that submits. Search does; the
  /// forms that have a button of their own below do not.
  final bool arrowSubmits;

  final TextInputAction textInputAction;

  /// Called when the text changes, after the state's notice is cleared.
  final VoidCallback? onChanged;

  final String? error;

  const LookupCard({
    super.key,
    required this.state,
    required this.onSubmit,
    this.arrowSubmits = false,
    this.textInputAction = TextInputAction.done,
    this.onChanged,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SurfaceCard(
              radius: AppTheme.radiusLg,
              padding: const EdgeInsets.all(AppTheme.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: LookupModePicker(
                      byUid: state.byUid,
                      locked: state.uidLocked,
                      onChanged: state.toggleUid,
                    ),
                  ),
                  const SizedBox(height: AppTheme.sm),
                  TextField(
                    controller: state.controller,
                    onSubmitted: (_) => onSubmit(),
                    onChanged: (_) {
                      state.clearNotice();
                      onChanged?.call();
                    },
                    textInputAction: textInputAction,
                    keyboardType: state.byUid
                        ? TextInputType.number
                        : TextInputType.text,
                    inputFormatters: state.byUid
                        ? uidOnlyInputFormatters
                        : null,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: state.byUid ? 'Numeric UID' : 'Player name',
                      prefixIcon: Icon(
                        state.byUid ? Icons.numbers : Icons.person_outline,
                        color: AppTheme.muted,
                      ),
                      suffixIcon: arrowSubmits
                          ? IconButton(
                              icon: const Icon(
                                Icons.arrow_forward,
                                color: AppTheme.accent,
                              ),
                              tooltip: 'Search',
                              onPressed: onSubmit,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: AppTheme.sm),
                  PlatformPicker(
                    selected: state.platform,
                    onChanged: state.selectPlatform,
                  ),
                  if (state.byUid)
                    const _FindYourUid()
                  else
                    UidSuggestion(
                      controller: state.controller,
                      searchByUid: state.byUid,
                      onUseUid: () => state.toggleUid(true),
                      otherwise: _SwitchHint(
                        onTap: () => state.toggleUid(true),
                      ),
                    ),
                ],
              ),
            ),
            if (error != null)
              _Banner(
                icon: Icons.error_outline,
                color: AppTheme.red,
                text: error!,
              ),
            if (state.notice != null)
              _Banner(
                icon: Icons.info_outline,
                color: AppTheme.accent,
                text: state.notice!,
              ),
          ],
        );
      },
    );
  }
}

/// The choice between searching by name and by UID: a small capsule with both
/// options always showing, in the look of the platform capsule below the field.
/// On a platform that has only UID, UID stays chosen, with a lock, and choosing
/// Name explains why it can't be.
class LookupModePicker extends StatelessWidget {
  final bool byUid;
  final bool locked;
  final ValueChanged<bool> onChanged;

  const LookupModePicker({
    super.key,
    required this.byUid,
    required this.onChanged,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return PillSegments(
      compact: true,
      options: [
        PillOption(
          label: 'Name',
          semanticLabel: 'Search by name',
          icon: (color) => Icon(Icons.person_outline, size: 14, color: color),
        ),
        PillOption(
          label: 'UID',
          semanticLabel: 'Search by UID',
          icon: (color) => Icon(Icons.numbers, size: 14, color: color),
          locked: locked,
        ),
      ],
      selected: byUid ? 1 : 0,
      onChanged: (i) => onChanged(i == 1),
    );
  }
}

/// Where to find a UID, shown while searching by one.
class _FindYourUid extends StatelessWidget {
  const _FindYourUid();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => openExternalLink(
            context,
            Uri.parse(ApiConstants.alsProfileSearchUrl),
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.xs, vertical: 2),
            // The open-in-new arrow says this leaves the app, as it does in
            // Settings.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Find your UID',
                    style: TextStyle(color: AppTheme.accent, fontSize: 13),
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.open_in_new, size: 13, color: AppTheme.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A standing line under the field while searching by name, so the other way
/// to search is never a secret.
class _SwitchHint extends StatelessWidget {
  final VoidCallback onTap;
  const _SwitchHint({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.xs, vertical: 2),
            child: Text.rich(
              TextSpan(
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
                children: [
                  TextSpan(text: 'Know their UID? '),
                  TextSpan(
                    text: 'Search by UID',
                    style: TextStyle(color: AppTheme.accent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Banner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.sm),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.sm),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: TextStyle(color: color, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
