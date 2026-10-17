import 'dart:ui';

import 'package:apexlytics/utils/ranked/label_placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bounds = Rect.fromLTWH(0, 0, 300, 200);
  const label = Size(40, 12);

  List<Rect?> place(List<Offset> centers, {Rect area = bounds}) => placeLabels(
    centers: centers,
    sizes: [for (final _ in centers) label],
    bounds: area,
  );

  test('a lone dot gets its label on the right', () {
    final r = place([const Offset(100, 100)]).single!;

    expect(r.left, greaterThan(100));
    expect(r.center.dy, 100);
  });

  test('moves to the left when the right would leave the area', () {
    final r = place([const Offset(280, 100)]).single!;

    expect(r.right, lessThan(280));
    expect(r.left, greaterThanOrEqualTo(0));
  });

  test('stays inside the area at a corner', () {
    final r = place([const Offset(5, 5)]).single!;

    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.top, greaterThanOrEqualTo(0));
  });

  test('never overlaps another label or any dot', () {
    final centers = [
      for (var i = 0; i < 8; i++) Offset(100 + i * 6.0, 100 + (i % 3) * 5.0),
    ];
    final placed = place(centers).nonNulls.toList();

    expect(placed, isNotEmpty);
    for (final (i, a) in placed.indexed) {
      for (final b in placed.skip(i + 1)) {
        expect(a.overlaps(b), isFalse);
      }
      for (final c in centers) {
        expect(a.overlaps(Rect.fromCircle(center: c, radius: 7)), isFalse);
      }
    }
  });

  test('the first dot gets the spot two labels both want', () {
    // Close enough that both labels would sit on the right and overlap.
    const a = Offset(100, 100);
    const b = Offset(100, 108);

    final ab = place([a, b]);
    expect(ab[0]!.left, greaterThan(a.dx));
    expect(ab[1]!.overlaps(ab[0]!), isFalse);

    final ba = place([b, a]);
    expect(ba[0]!.left, greaterThan(b.dx));
  });

  test('a label with no room is left off, not drawn over another', () {
    const tiny = Rect.fromLTWH(80, 90, 40, 24);

    expect(place([const Offset(100, 100)], area: tiny).single, isNull);
  });
}
