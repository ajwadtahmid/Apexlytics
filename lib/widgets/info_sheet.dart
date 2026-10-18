import 'package:flutter/material.dart';

import '../utils/theme.dart';
import 'sheet_handle.dart';

/// A short "how to read this" bottom sheet: a handle, a [title], then one
/// paragraph per entry of [lines]. Scrolls when the text outgrows the screen.
Future<void> showInfoSheet(
  BuildContext context, {
  required String title,
  required List<String> lines,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: AppTheme.md),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTheme.md),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.sm),
                child: Text(line, style: AppTheme.captionLarge),
              ),
          ],
        ),
      ),
    ),
  );
}
