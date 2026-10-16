import 'package:flutter/material.dart';

import '../utils/theme.dart';

/// The bottom sheet drag handle, in the size and colour the theme defines.
/// For sheets that lay out their own header, where `showDragHandle` doesn't fit.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).bottomSheetTheme;
    final size = theme.dragHandleSize ?? const Size(36, 4);
    return Center(
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: theme.dragHandleColor ?? AppTheme.muted,
          borderRadius: BorderRadius.circular(size.height / 2),
        ),
      ),
    );
  }
}
