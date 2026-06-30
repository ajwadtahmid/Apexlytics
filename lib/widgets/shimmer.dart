import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../utils/theme.dart';

// Wrap any skeleton tree in this once at the top level so every ShimmerBox
// inside shares a single animation and sweeps in sync.

class ShimmerWrapper extends StatelessWidget {
  final Widget child;
  const ShimmerWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.surface2,
      highlightColor: AppTheme.shimmerHighlight,
      child: child,
    );
  }
}

// A solid white rectangle — Shimmer.fromColors replaces its paint with the
// sweeping gradient. Must be a descendant of ShimmerWrapper.

class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppTheme.radiusSm),
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius,
      ),
    );
  }
}
