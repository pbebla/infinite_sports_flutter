import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_match_detail.dart';
import 'package:infinite_sports_flutter/league_team_detail.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_navigation.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

Future<BuildContext> _context(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }),
  ));
  return ctx;
}

void main() {
  testWidgets(
      'leagueMatchRoute builds LeagueMatchDetailPage with the game\'s date key and index',
      (tester) async {
    final ctx = await _context(tester);
    final match = leagueMatchesFromDateNode({
      '06152026': [
        {'team1': 'A', 'team2': 'B', 'team1score': 0, 'team2score': 0, 'status': 0},
        {'team1': 'C', 'team2': 'D', 'team1score': 0, 'team2score': 0, 'status': 0},
      ],
    })[1];
    final route =
        leagueMatchRoute(sport: 'Futsal', season: '16', match: match)!;
    final page = route.builder(ctx) as LeagueMatchDetailPage;
    expect(page.sport, 'Futsal');
    expect(page.season, '16');
    expect(page.dateKey, '06152026');
    expect(page.gameIndex, 1);
    expect(page.initialMatch, same(match));
  });

  test('leagueMatchRoute is null for an id that is not a league game id', () {
    final m = TournamentMatch(id: 'm1', stage: 's', label: 'l', date: 'd', team1Id: 'A', team2Id: 'B', team1Score: 0, team2Score: 0, status: 0, bracketPosition: 0);
    expect(leagueMatchRoute(sport: 'Futsal', season: '16', match: m), isNull);
  });

  testWidgets('leagueTeamRoute builds LeagueTeamDetailPage for that team',
      (tester) async {
    final ctx = await _context(tester);
    final route = leagueTeamRoute(
        sport: 'Futsal', season: '16', teamName: 'Alpha FC');
    final page = route.builder(ctx) as LeagueTeamDetailPage;
    expect(page.sport, 'Futsal');
    expect(page.season, '16');
    expect(page.teamName, 'Alpha FC');
  });
}
