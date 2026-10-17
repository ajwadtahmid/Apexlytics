import 'dart:ui' show Offset, Rect, Size;

/// Which side of its dot a label sits on. The last four sit to the side but a
/// little up or down, for dots with a neighbour right beside them.
enum LabelSide {
  right,
  left,
  above,
  below,
  rightUp,
  rightDown,
  leftUp,
  leftDown,
}

/// Where each label goes: beside its dot on the first side that stays inside
/// [bounds] and clear of every dot and every label already placed. Null for a
/// label that fits nowhere, which is better left off than drawn over another.
///
/// [centers] and [sizes] run in priority order, so the earlier labels get the
/// good spots. [radius] is the dots' radius and [gap] the space between a dot
/// and its label.
List<Rect?> placeLabels({
  required List<Offset> centers,
  required List<Size> sizes,
  required Rect bounds,
  double radius = 7,
  double gap = 3,
}) {
  assert(centers.length == sizes.length);
  final dots = [
    for (final c in centers) Rect.fromCircle(center: c, radius: radius),
  ];
  final placed = <Rect>[];
  final reach = radius + gap;

  Rect beside(Offset c, Size s, LabelSide side) => switch (side) {
    LabelSide.right => Rect.fromLTWH(
      c.dx + reach,
      c.dy - s.height / 2,
      s.width,
      s.height,
    ),
    LabelSide.left => Rect.fromLTWH(
      c.dx - reach - s.width,
      c.dy - s.height / 2,
      s.width,
      s.height,
    ),
    LabelSide.above => Rect.fromLTWH(
      c.dx - s.width / 2,
      c.dy - reach - s.height,
      s.width,
      s.height,
    ),
    LabelSide.below => Rect.fromLTWH(
      c.dx - s.width / 2,
      c.dy + reach,
      s.width,
      s.height,
    ),
    LabelSide.rightUp => beside(
      c,
      s,
      LabelSide.right,
    ).shift(Offset(0, -s.height * 0.8)),
    LabelSide.rightDown => beside(
      c,
      s,
      LabelSide.right,
    ).shift(Offset(0, s.height * 0.8)),
    LabelSide.leftUp => beside(
      c,
      s,
      LabelSide.left,
    ).shift(Offset(0, -s.height * 0.8)),
    LabelSide.leftDown => beside(
      c,
      s,
      LabelSide.left,
    ).shift(Offset(0, s.height * 0.8)),
  };

  bool fits(Rect r) =>
      r.left >= bounds.left &&
      r.right <= bounds.right &&
      r.top >= bounds.top &&
      r.bottom <= bounds.bottom &&
      !dots.any(r.overlaps) &&
      !placed.any(r.overlaps);

  Rect? place(int i) {
    for (final side in LabelSide.values) {
      final r = beside(centers[i], sizes[i], side);
      if (fits(r)) {
        placed.add(r);
        return r;
      }
    }
    return null;
  }

  return [for (var i = 0; i < centers.length; i++) place(i)];
}
