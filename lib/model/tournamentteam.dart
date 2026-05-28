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
  final String? homeColor;
  final String? awayColor;
  final String? overrideColor;
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
      name: teamData['Name']?.toString() ?? teamData['name']?.toString() ?? id,
      logoUrl: teamData['LogoUrl']?.toString() ?? teamData['logoUrl']?.toString(),
      seed: (teamData['Seed'] as num?)?.toInt() ?? (teamData['seed'] as num?)?.toInt(),
      group: teamData['Group']?.toString() ?? teamData['group']?.toString(),
      qualification: teamData['Qualification']?.toString() ??
          teamData['qualification']?.toString() ??
          tableData['Qualification']?.toString() ??
          tableData['qualification']?.toString() ??
          'TBD',
      gp: (tableData['GP'] as num?)?.toInt() ?? (tableData['gp'] as num?)?.toInt() ?? 0,
      wins: (tableData['W'] as num?)?.toInt() ?? (tableData['wins'] as num?)?.toInt() ?? 0,
      draws: (tableData['D'] as num?)?.toInt() ?? (tableData['draws'] as num?)?.toInt() ?? 0,
      losses: (tableData['L'] as num?)?.toInt() ?? (tableData['losses'] as num?)?.toInt() ?? 0,
      gs: (tableData['GS'] as num?)?.toInt() ?? (tableData['gs'] as num?)?.toInt() ?? 0,
      gc: (tableData['GC'] as num?)?.toInt() ?? (tableData['gc'] as num?)?.toInt() ?? 0,
      gd: (tableData['GD'] as num?)?.toInt() ?? (tableData['gd'] as num?)?.toInt() ?? 0,
      points: (tableData['Pts'] as num?)?.toInt() ??
          (tableData['pts'] as num?)?.toInt() ??
          (tableData['Points'] as num?)?.toInt() ??
          0,
      homeColor: teamData['HomeColor']?.toString() ?? teamData['homeColor']?.toString(),
      awayColor: teamData['AwayColor']?.toString() ?? teamData['awayColor']?.toString(),
      overrideColor: teamData['OverrideColor']?.toString() ?? teamData['overrideColor']?.toString(),
      coachName: teamData['CoachName']?.toString() ?? teamData['coachName']?.toString(),
      coachPhotoUrl: teamData['CoachPhotoUrl']?.toString() ?? teamData['coachPhotoUrl']?.toString(),
      cityState: teamData['CityState']?.toString() ?? teamData['cityState']?.toString(),
      established: teamData['Established']?.toString() ?? teamData['established']?.toString(),
    );
  }
}
