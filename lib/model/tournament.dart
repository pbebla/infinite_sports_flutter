class Tournament {
  final String id;
  final String name;
  final String sport;
  final String edition;
  final String? logoUrl;
  final String? hostCity;
  final String? location;
  final String? startDate;
  final String? endDate;
  final String status;
  final bool finished;
  final String? champion;
  final String? runnerUp;
  final String? goldenBoot;
  final String? bestKeeper;
  final String? dplLeader;

  const Tournament({
    required this.id,
    required this.name,
    required this.sport,
    required this.edition,
    this.logoUrl,
    this.hostCity,
    this.location,
    this.startDate,
    this.endDate,
    required this.status,
    required this.finished,
    this.champion,
    this.runnerUp,
    this.goldenBoot,
    this.bestKeeper,
    this.dplLeader,
  });

  factory Tournament.fromFirebase(String id, Map<dynamic, dynamic> data) {
    return Tournament(
      id: id,
      name: data['Name']?.toString() ?? data['name']?.toString() ?? id,
      sport: data['Sport']?.toString() ?? data['sport']?.toString() ?? 'Soccer',
      edition: data['Edition']?.toString() ?? data['edition']?.toString() ?? '',
      logoUrl: data['LogoUrl']?.toString() ?? data['logoUrl']?.toString(),
      hostCity: data['HostCity']?.toString() ?? data['hostCity']?.toString(),
      location: data['Location']?.toString() ?? data['location']?.toString(),
      startDate: data['StartDate']?.toString() ?? data['startDate']?.toString(),
      endDate: data['EndDate']?.toString() ?? data['endDate']?.toString(),
      status: data['Status']?.toString() ?? data['status']?.toString() ?? 'TBD',
      finished: data['Finished'] as bool? ?? data['finished'] as bool? ?? false,
      champion: data['Champion']?.toString() ?? data['champion']?.toString(),
      runnerUp: data['RunnerUp']?.toString() ?? data['runnerUp']?.toString(),
      goldenBoot: data['GoldenBoot']?.toString() ?? data['goldenBoot']?.toString(),
      bestKeeper: data['BestKeeper']?.toString() ?? data['bestKeeper']?.toString(),
      dplLeader: data['DplLeader']?.toString() ?? data['dplLeader']?.toString(),
    );
  }
}
