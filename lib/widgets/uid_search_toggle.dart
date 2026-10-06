import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/api_constants.dart';
import '../utils/theme.dart';

/// Apply to a [TextField.inputFormatters] whenever UID search mode is active,
/// so a mistyped character or a pasted name never reaches the network as a
/// "UID" — every platform's UID is numeric, so this can never reject a value
/// that would have worked anyway.
final uidOnlyInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
];

/// Whether [text] is non-empty and safe to submit as a UID.
bool isDigitsOnly(String text) =>
    text.isNotEmpty && RegExp(r'^\d+$').hasMatch(text);

/// Fewest digits that read as a UID rather than a numeric name. Apex UIDs are 10+ digits.
const _kMinUidDigits = 8;

/// Whether [text] is long and numeric enough to be a UID typed into the name field.
bool looksLikeUid(String text) =>
    text.length >= _kMinUidDigits && isDigitsOnly(text);

/// "Looks like a UID" hint shown under the name field when [controller] holds digits only.
/// Hidden in UID mode. Tapping the action calls [onUseUid], which should switch to UID search.
class UidSuggestion extends StatelessWidget {
  final TextEditingController controller;
  final bool searchByUid;
  final VoidCallback onUseUid;

  const UidSuggestion({
    super.key,
    required this.controller,
    required this.searchByUid,
    required this.onUseUid,
  });

  @override
  Widget build(BuildContext context) {
    if (searchByUid) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!looksLikeUid(controller.text.trim())) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: AppTheme.sm),
          child: InkWell(
            onTap: onUseUid,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            child: Container(
              padding: const EdgeInsets.all(AppTheme.sm),
              decoration: BoxDecoration(
                color: AppTheme.accent.withAlpha(30),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: const Row(
                children: [
                  Icon(Icons.numbers, size: 16, color: AppTheme.accent),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Looks like a UID. Tap to search by UID.',
                      style: TextStyle(color: AppTheme.accent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A row with an icon, "Search by UID" label, and a Switch.
/// Used in both the Search bar and the Stats player-lookup form.
class UidSearchToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const UidSearchToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  Future<void> _openLink() async {
    await launchUrl(
      Uri.parse(ApiConstants.alsProfileSearchUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.numbers, size: 16, color: AppTheme.muted),
        const SizedBox(width: AppTheme.sm),
        Expanded(
          child: Row(
            children: [
              const Text(
                'Search by UID ',
                style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              ),
              InkWell(
                onTap: _openLink,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: const Text(
                  '(Find your UID)',
                  style: TextStyle(fontSize: 13, color: AppTheme.accent),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppTheme.accent,
        ),
      ],
    );
  }
}
