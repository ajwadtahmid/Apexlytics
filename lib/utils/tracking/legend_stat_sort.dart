import '../../constants/legend_constants.dart';
import '../../models/player_stats.dart';

/// An order the Legends tab can list legends in.
enum LegendStatSort {
  recent('Recent'),
  kills('Kills'),
  damage('Damage'),
  wins('Wins'),
  role('Role');

  final String label;
  const LegendStatSort(this.label);
}

/// [legends] ordered by [sort]. Each order starts with its natural end: the
/// most recently visited, the biggest figure, the first role. [reversed] flips
/// that. Ties keep the order the legends came in.
///
/// [recentStack] is the visit order for [LegendStatSort.recent], most recent
/// first; legends not in it follow in their own order.
List<LegendStat> sortLegendStats(
  List<LegendStat> legends,
  LegendStatSort sort, {
  List<String> recentStack = const [],
  bool reversed = false,
}) {
  final list = [...legends];
  final index = {for (var i = 0; i < list.length; i++) list[i].name: i};
  int byIndex(LegendStat a, LegendStat b) =>
      index[a.name]!.compareTo(index[b.name]!);

  // The figures to compare, most important first; only the first honours
  // [reversed], the rest only break ties.
  final List<num Function(LegendStat)>? figures = switch (sort) {
    LegendStatSort.kills => [
      (l) => l.killCount,
      (l) => l.damageDealt,
      (l) => l.winsCount,
    ],
    LegendStatSort.damage => [
      (l) => l.damageDealt,
      (l) => l.killCount,
      (l) => l.winsCount,
    ],
    LegendStatSort.wins => [
      (l) => l.winsCount,
      (l) => l.killCount,
      (l) => l.damageDealt,
    ],
    LegendStatSort.recent || LegendStatSort.role => null,
  };

  if (figures != null) {
    return list..sort((a, b) {
      for (var i = 0; i < figures.length; i++) {
        final x = figures[i](a);
        final y = figures[i](b);
        final c = i == 0 && reversed ? x.compareTo(y) : y.compareTo(x);
        if (c != 0) return c;
      }
      return byIndex(a, b);
    });
  }

  if (sort == LegendStatSort.recent) {
    if (recentStack.isNotEmpty) {
      list.sort((a, b) {
        final ia = recentStack.indexOf(a.name);
        final ib = recentStack.indexOf(b.name);
        if (ia == -1 && ib == -1) return byIndex(a, b);
        if (ia == -1) return 1;
        if (ib == -1) return -1;
        return ia.compareTo(ib);
      });
    }
  } else {
    list.sort((a, b) {
      final roleA = legendInfo(a.name)?.role ?? LegendRole.assault;
      final roleB = legendInfo(b.name)?.role ?? LegendRole.assault;
      final byRole = kRoleDisplayOrder
          .indexOf(roleA)
          .compareTo(kRoleDisplayOrder.indexOf(roleB));
      if (byRole != 0) return byRole;
      final byNumber = (legendInfo(a.name)?.number ?? 999).compareTo(
        legendInfo(b.name)?.number ?? 999,
      );
      return byNumber != 0 ? byNumber : byIndex(a, b);
    });
  }
  return reversed ? list.reversed.toList() : list;
}
