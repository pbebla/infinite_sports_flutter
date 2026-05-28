import 'dart:ui' show Color;
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

/// Parses a hex string like "#RRGGBB" or "RRGGBB" (or 8-char with alpha)
/// into a [Color]. Returns null if the input is null/empty/invalid.
Color? _parseHexColor(dynamic value) {
  if (value == null) return null;
  var clean = value.toString().trim();
  if (clean.isEmpty) return null;
  if (clean.startsWith('#')) clean = clean.substring(1);
  if (clean.length == 6) clean = 'FF$clean';
  if (clean.length != 8) return null;
  final intValue = int.tryParse(clean, radix: 16);
  if (intValue == null) return null;
  return Color(intValue);
}

class TournamentTeam {
  final String id;
  final String name;
  final String? logoUrl;
  final int? seed;
  final String qualification;

  /// Which group this team belongs to, e.g. "Group A". Null for single-group tournaments.
  final String? group;
  final int gp;
  final int wins;
  final int draws;
  final int losses;
  final int gs;
  final int gc;
  final int gd;
  final int points;
  final Color? homeColor;
  final Color? awayColor;
  final Color? overrideColor;
  final String? coachName;
  final String? coachPhotoUrl;
  final String? cityState;
  final String? established;

  const TournamentTeam({
    required this.id,
    required this.name,
    this.logoUrl,
    this.seed,
    required this.qualification,
    this.group,
    required this.gp,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.gs,
    required this.gc,
    required this.gd,
    required this.points,
    this.homeColor,
    this.awayColor,
    this.overrideColor,
    this.coachName,
    this.coachPhotoUrl,
    this.cityState,
    this.established,
  });

  factory TournamentTeam.fromFirebase(
    String id,
    Map<dynamic, dynamic> teamData,
    Map<dynamic, dynamic> tableData,
  ) {
    return TournamentTeam(
      id: id,
      name: firstNonNull(teamData, ['Name', 'name'])?.toString() ?? id,
      logoUrl: firstNonNull(teamData, ['LogoUrl', 'logoUrl'])?.toString(),
      seed: firstNonNull(teamData, ['Seed', 'seed']) != null
          ? parseInt(firstNonNull(teamData, ['Seed', 'seed']))
          : null,
      group: firstNonNull(teamData, ['Group', 'group'])?.toString(),
      qualification: firstNonNull(teamData, ['Qualification', 'qualification'])?.toString() ??
          firstNonNull(tableData, ['Qualification', 'qualification'])?.toString() ??
          'TBD',
      gp: parseInt(firstNonNull(tableData, ['GP', 'gp'])),
      wins: parseInt(firstNonNull(tableData, ['W', 'wins'])),
      draws: parseInt(firstNonNull(tableData, ['D', 'draws'])),
      losses: parseInt(firstNonNull(tableData, ['L', 'losses'])),
      gs: parseInt(firstNonNull(tableData, ['GS', 'gs'])),
      gc: parseInt(firstNonNull(tableData, ['GC', 'gc'])),
      gd: parseInt(firstNonNull(tableData, ['GD', 'gd'])),
      points: parseInt(firstNonNull(tableData, ['Pts', 'pts', 'Points'])),
      homeColor: _parseHexColor(firstNonNull(teamData, ['HomeColor', 'homeColor'])),
      awayColor: _parseHexColor(firstNonNull(teamData, ['AwayColor', 'awayColor'])),
      overrideColor: _parseHexColor(firstNonNull(teamData, ['OverrideColor', 'overrideColor'])),
      coachName: firstNonNull(teamData, ['CoachName', 'coachName'])?.toString(),
      coachPhotoUrl: firstNonNull(teamData, ['CoachPhotoUrl', 'coachPhotoUrl'])?.toString(),
      cityState: firstNonNull(teamData, ['CityState', 'cityState'])?.toString(),
      established: firstNonNull(teamData, ['Established', 'established'])?.toString(),
    );
  }
}
