import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// The icon for each figure the app shows, in one place so a figure wears the
/// same icon on every screen: the Rank by picker, the sort sheets, the share
/// cards and the Records page.
///
/// An average is a rate (aimed for, a crosshair or a bullseye); a total is a
/// tally (the fallen, the damage done). Font Awesome icons are used through
/// their plain [IconData], so they go wherever a Material icon does.
abstract final class StatIcons {
  /// RP gained or lost, added up.
  static const totalRp = Icons.bar_chart;

  /// RP gained or lost in an average game.
  static const avgRp = Icons.show_chart;

  /// The share of games that gained RP.
  static const winRate = Icons.percent;

  /// Games won, counted (a legend's wins on the All Trackers page).
  static const wins = Icons.emoji_events;

  /// The number of games played: a count, so a hashtag, not a game controller.
  static const games = Icons.tag;

  /// Time played.
  static const time = Icons.schedule;

  /// Consecutive wins.
  static const winStreak = Icons.military_tech;

  /// Kills in an average game, and all of them.
  static final avgKills = FontAwesomeIcons.crosshairs.data;
  static final totalKills = FontAwesomeIcons.skull.data;

  /// Damage in an average game, and all of it.
  static final avgDamage = FontAwesomeIcons.bullseye.data;
  static const totalDamage = Icons.local_fire_department;
}
