import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

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
      name: firstNonNull(data, ['Name', 'name'])?.toString() ?? id,
      sport: firstNonNull(data, ['Sport', 'sport'])?.toString() ?? 'Soccer',
      edition: firstNonNull(data, ['Edition', 'edition'])?.toString() ?? '',
      logoUrl: firstNonNull(data, ['LogoUrl', 'logoUrl'])?.toString(),
      hostCity: firstNonNull(data, ['HostCity', 'hostCity'])?.toString(),
      location: firstNonNull(data, ['Location', 'location'])?.toString(),
      startDate: firstNonNull(data, ['StartDate', 'startDate'])?.toString(),
      endDate: firstNonNull(data, ['EndDate', 'endDate'])?.toString(),
      status: firstNonNull(data, ['Status', 'status'])?.toString() ?? 'TBD',
      finished: parseBool(firstNonNull(data, ['Finished', 'finished'])),
      champion: firstNonNull(data, ['Champion', 'champion'])?.toString(),
      runnerUp: firstNonNull(data, ['RunnerUp', 'runnerUp'])?.toString(),
      goldenBoot: firstNonNull(data, ['GoldenBoot', 'goldenBoot'])?.toString(),
      bestKeeper: firstNonNull(data, ['BestKeeper', 'bestKeeper'])?.toString(),
      dplLeader: firstNonNull(data, ['DplLeader', 'dplLeader'])?.toString(),
    );
  }
}
