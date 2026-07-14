// Widget tests for the league team page's Firebase-free tab bodies
// (P2.1 Task A3: tournament-team-page structure, season-scoped).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_team_detail.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_form.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

TournamentTeam _team({String? colorHex, String? coach}) =>
    leagueStandingsFromTeamsNode('Futsal', {
      'Nineveh': {
        'Wins': 4, 'Draws': 1, 'Losses': 2, 'GP': 7,
        'GS': 15, 'GC': 9, 'GD': 6, 'Points': 13,
        if (coach != null) 'Coach': coach,
        if (colorHex != null) 'Color': colorHex,
      },
    }, const {}).single;

List<TournamentPlayer> _roster() =>
    leagueRostersFromLineupsNode('Futsal', {
      'Nineveh': {
        'Ashur': {'Goals': 7, 'Assists': 2, 'number': '10', 'UID': 'uid-1'},
        'Sargon': {'Saves': 12, 'CleanSheets': 3, 'number': '1'},
        'Ninos': {'number': '7'}, // zero stats -> excluded from leaders
      },
    })['Nineveh']!;

List<TournamentMatch> _matches() => teamLeagueMatches(
      'Nineveh',
      leagueMatchesFromDateNode({
        '06152026': [
          {'team1': 'Nineveh', 'team2': 'Babylon', 'team1score': 3, 'team2score': 1, 'status': 2},
        ],
        '06222026': [
          {'team1': 'Akkad', 'team2': 'Nineveh', 'team1score': 0, 'team2score': 0, 'status': 0},
        ],
      }),
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('LeagueTeamOverviewTab', () {
    testWidgets(
        'shows Captain (tappable when in squad), Players count, League Record'
        ' and keeps results & fixtures BELOW the record box', (tester) async {
      TournamentPlayer? tappedPlayer;
      TournamentMatch? tappedMatch;
      await tester.pumpWidget(_wrap(LeagueTeamOverviewTab(
        team: _team(coach: 'Zaya'),
        captain: 'Ashur',
        roster: _roster(),
        matches: _matches(),
        standingsLoaded: true,
        matchesLoaded: true,
        rosterLoaded: true,
        onMatchTap: (m) => tappedMatch = m,
        onPlayerTap: (p) => tappedPlayer = p,
      )));

      // Team Info: Captain + Players (replaces Established/City).
      expect(find.text('Captain: '), findsOneWidget);
      expect(find.text('Ashur'), findsOneWidget);
      expect(find.text('Players: 3'), findsOneWidget);

      // Coaching staff card.
      expect(find.text('Coaching Staff'), findsOneWidget);
      expect(find.text('Zaya'), findsOneWidget);

      // League Record box (not "Tournament Record") with this season's row.
      expect(find.text('League Record'), findsOneWidget);
      expect(find.text('Tournament Record'), findsNothing);
      expect(find.text('13'), findsOneWidget); // Pts
      expect(find.text('+6'), findsOneWidget); // GD

      // Results & fixtures kept, below the record box.
      expect(find.text('RESULTS & FIXTURES'), findsOneWidget);
      expect(find.text('Nineveh vs Babylon'), findsOneWidget);
      final recordY = tester.getTopLeft(find.text('League Record')).dy;
      final resultsY = tester.getTopLeft(find.text('RESULTS & FIXTURES')).dy;
      expect(recordY, lessThan(resultsY));

      // Captain row taps through to the squad player.
      await tester.tap(find.text('Ashur'));
      expect(tappedPlayer?.name, 'Ashur');
      expect(tappedPlayer?.uid, 'uid-1');

      // Match rows still open the match page.
      await tester.tap(find.text('Nineveh vs Babylon'));
      expect(tappedMatch?.id, '06152026#0');
    });

    testWidgets('captain unset shows an em dash and is not tappable',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(LeagueTeamOverviewTab(
        team: _team(),
        captain: null,
        roster: _roster(),
        matches: const [],
        standingsLoaded: true,
        matchesLoaded: true,
        rosterLoaded: true,
        onMatchTap: (_) {},
        onPlayerTap: (_) => taps++,
      )));
      expect(find.text('—'), findsOneWidget);
      await tester.tap(find.text('—'));
      expect(taps, 0);
      expect(find.text('No games scheduled yet'), findsOneWidget);
    });

    testWidgets(
        'captain named but NOT in the squad renders plain (not tappable)',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(LeagueTeamOverviewTab(
        team: _team(),
        captain: 'Ghost Player',
        roster: _roster(),
        matches: const [],
        standingsLoaded: true,
        matchesLoaded: true,
        rosterLoaded: true,
        onMatchTap: (_) {},
        onPlayerTap: (_) => taps++,
      )));
      expect(find.text('Ghost Player'), findsOneWidget);
      await tester.tap(find.text('Ghost Player'));
      expect(taps, 0);
    });

    testWidgets('jersey card shows only when the Color parses',
        (tester) async {
      await tester.pumpWidget(_wrap(LeagueTeamOverviewTab(
        team: _team(colorHex: '#1A237E'),
        captain: null,
        roster: const [],
        matches: const [],
        standingsLoaded: true,
        matchesLoaded: true,
        rosterLoaded: true,
        onMatchTap: (_) {},
        onPlayerTap: (_) {},
      )));
      expect(find.text('Jersey Color'), findsOneWidget);

      await tester.pumpWidget(_wrap(LeagueTeamOverviewTab(
        team: _team(), // no Color key -> homeColor null -> card hidden
        captain: null,
        roster: const [],
        matches: const [],
        standingsLoaded: true,
        matchesLoaded: true,
        rosterLoaded: true,
        onMatchTap: (_) {},
        onPlayerTap: (_) {},
      )));
      expect(find.text('Jersey Color'), findsNothing);
      expect(find.text('Coaching Staff'), findsNothing); // no coach either
    });
  });

  group('LeagueTeamSquadTab', () {
    /// The stat chips inside the squad row that contains [playerName].
    Finder chipsOf(String playerName) => find.descendant(
          of: find.ancestor(
              of: find.text(playerName), matching: find.byType(InkWell)),
          matching: find.byType(StatIcon),
        );

    /// A value text inside [playerName]'s squad row.
    Finder rowText(String playerName, String text) => find.descendant(
          of: find.ancestor(
              of: find.text(playerName), matching: find.byType(InkWell)),
          matching: find.text(text),
        );

    testWidgets('coach section + number-sorted players with profile taps',
        (tester) async {
      TournamentPlayer? tapped;
      await tester.pumpWidget(_wrap(LeagueTeamSquadTab(
        coach: 'Zaya',
        roster: _roster(),
        rosterLoaded: true,
        onPlayerTap: (p) => tapped = p,
      )));
      expect(find.text('COACHING STAFF'), findsOneWidget);
      expect(find.text('Zaya'), findsOneWidget);
      expect(find.text('PLAYERS'), findsOneWidget);
      // Adapter sorts by shirt number: 1, 7, 10.
      final sargonY = tester.getTopLeft(find.text('Sargon')).dy;
      final ashurY = tester.getTopLeft(find.text('Ashur')).dy;
      expect(sargonY, lessThan(ashurY));

      await tester.tap(find.text('Ashur'));
      expect(tapped?.name, 'Ashur');
    });

    testWidgets(
        'P2.2: every player row has a photo slot (person fallback) and its'
        ' top-3 stat chips, fallback-filled with zeros', (tester) async {
      await tester.pumpWidget(_wrap(LeagueTeamSquadTab(
        coach: null,
        roster: _roster(),
        rosterLoaded: true,
        onPlayerTap: (_) {},
      )));

      // One avatar per player: TeamLogo with the neutral person fallback
      // (no coach section here, so exactly the 3 roster rows).
      expect(
        find.byWidgetPredicate((w) =>
            w is TeamLogo && w.url == null && w.fallbackIcon == Icons.person),
        findsNWidgets(3),
      );

      // 3 chips per player, always (fallback fills to 3).
      expect(chipsOf('Ashur'), findsNWidgets(3));
      expect(chipsOf('Sargon'), findsNWidgets(3));
      expect(chipsOf('Ninos'), findsNWidgets(3));

      // Ashur (G7 A2): goals 7, assists 2, then DPL 0 from the fallback.
      expect(rowText('Ashur', '7'), findsOneWidget);
      expect(rowText('Ashur', '2'), findsOneWidget);
      expect(rowText('Ashur', '0'), findsOneWidget);
      // Sargon (SV12 CS3): saves 12, clean sheets 3, then goals 0.
      expect(rowText('Sargon', '12'), findsOneWidget);
      expect(rowText('Sargon', '3'), findsOneWidget);
      expect(rowText('Sargon', '0'), findsOneWidget);
      // Ninos (all zero): the full fallback at 0.
      expect(rowText('Ninos', '0'), findsNWidgets(3));
    });

    testWidgets('P2.2: linked player with a profile photo gets it on the row',
        (tester) async {
      final withPhoto = [
        _roster().first.copyWith(photoUrl: 'http://pic/sargon.jpg'),
      ];
      await tester.pumpWidget(_wrap(LeagueTeamSquadTab(
        coach: null,
        roster: withPhoto,
        rosterLoaded: true,
        onPlayerTap: (_) {},
      )));
      expect(
        find.byWidgetPredicate(
            (w) => w is TeamLogo && w.url == 'http://pic/sargon.jpg'),
        findsOneWidget,
      );
    });

    testWidgets('no coach -> no staff section; empty roster note',
        (tester) async {
      await tester.pumpWidget(_wrap(LeagueTeamSquadTab(
        coach: null,
        roster: const [],
        rosterLoaded: true,
        onPlayerTap: (_) {},
      )));
      expect(find.text('COACHING STAFF'), findsNothing);
      expect(find.text('No roster yet'), findsOneWidget);
    });
  });

  group('LeagueTeamStatsTab', () {
    testWidgets(
        'season-total leader cards: zero counts excluded, leader circled',
        (tester) async {
      await tester.pumpWidget(_wrap(LeagueTeamStatsTab(
        roster: _roster(),
        rosterLoaded: true,
        onPlayerTap: (_) {},
      )));
      expect(find.text('Goals'), findsOneWidget);
      expect(find.text('Saves'), findsOneWidget);
      expect(find.text('Clean Sheets'), findsOneWidget);
      // Nobody has cards this season -> categories absent.
      expect(find.text('Yellow Cards'), findsNothing);
      // Zero-stat player appears in no category.
      expect(find.text('Ninos'), findsNothing);
      expect(find.text('7'), findsOneWidget); // Ashur's goals
      expect(find.text('12'), findsOneWidget); // Sargon's saves

      // P2.2 owner item 3: category headers carry the same stat icons as
      // the league Player Stats tab (Clean Sheets stays iconless there
      // too) — Goals/Assists/Saves rendered here -> 3 icons.
      expect(
        find.byWidgetPredicate(
            (w) => w is StatIcon && w.asset == 'assets/goal.png'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
            (w) => w is StatIcon && w.asset == 'assets/save.png'),
        findsOneWidget,
      );
      expect(find.byType(StatIcon), findsNWidgets(3));
    });

    testWidgets('stat rows tap through to player profiles', (tester) async {
      TournamentPlayer? tapped;
      await tester.pumpWidget(_wrap(LeagueTeamStatsTab(
        roster: _roster(),
        rosterLoaded: true,
        onPlayerTap: (p) => tapped = p,
      )));
      await tester.tap(find.text('Sargon').first);
      expect(tapped?.name, 'Sargon');
    });

    testWidgets('empty roster shows the placeholder', (tester) async {
      await tester.pumpWidget(_wrap(LeagueTeamStatsTab(
        roster: const [],
        rosterLoaded: true,
        onPlayerTap: (_) {},
      )));
      expect(find.text('No player data'), findsOneWidget);
    });
  });
}
