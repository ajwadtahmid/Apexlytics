import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
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
      Uri.parse('https://apexlegendsstatus.com/profile/search/'),
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
