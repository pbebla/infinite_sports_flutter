import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_facts_tab.dart';
import 'package:infinite_sports_flutter/widgets/futsal_period_labels.dart';

Map<String, dynamic> _foul(String who, int t) => {'Foul': who, '_t': t};

Map<dynamic, dynamic> _game({
  int status = 1,
  String? period = '1H',
  Map<String, dynamic>? starts,
  List<Map<String, dynamic>> t1 = const [],
  List<Map<String, dynamic>> t2 = const [],
}) =>
    {
      'team1': 'Nineveh',
      'team2': 'Babylon',
      'team1score': 1,
      'team2score': 0,
      'status': status,
      if (period != null) 'Period': period,
      if (starts != null) 'PeriodStarts': starts,
      'team1activity': {"3'": t1},
      'team2activity': {"4'": t2},
    };

TournamentMatch _m(Map<dynamic, dynamic> raw, {String sport = 'Futsal'}) =>
    leagueMatchFromGameMap(
        dateKey: '06152026', index: 0, raw: raw, sport: sport);

Widget _header(TournamentMatch m, {bool dark = false, double width = 360}) {
  return MaterialApp(
    theme: dark ? ThemeData.dark() : ThemeData.light(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: Row(
            children: [
              Expanded(
                  child: Column(children: [
                const Text('Nineveh'),
                FutsalTeamFouls(match: m, team: 1),
              ])),
              Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('LIVE'),
                FutsalHalfLabel(match: m),
              ]),
              Expanded(
                  child: Column(children: [
                const Text('Babylon'),
                FutsalTeamFouls(match: m, team: 2),
              ])),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('adapter periodInfo', () {
    test('futsal game with Period gets periodInfo', () {
      expect(_m(_game()).periodInfo, isNotNull);
    });
    test('no Period -> null; basketball -> null', () {
      expect(_m(_game(period: null)).periodInfo, isNull);
      expect(_m(_game(), sport: 'Basketball').periodInfo, isNull);
    });
  });

  group('header labels', () {
    testWidgets('live 1st half shows label and per-team fouls', (t) async {
      final m =
          _m(_game(t1: [_foul('A', 1000), _foul('B', 2000), _foul('C', 3000)]));
      await t.pumpWidget(_header(m));
      expect(find.text('1st half'), findsOneWidget);
      expect(find.text('Fouls 3'), findsOneWidget);
      expect(find.text('Fouls 0'), findsOneWidget);
    });

    testWidgets('half time keeps the 1st-half counts', (t) async {
      final m = _m(_game(period: 'HT', t1: [_foul('A', 1000)]));
      await t.pumpWidget(_header(m));
      expect(find.text('Half time'), findsOneWidget);
      expect(find.text('Fouls 1'), findsOneWidget);
    });

    testWidgets('2nd half counts only 2nd-half fouls', (t) async {
      final m = _m(_game(
        period: '2H',
        starts: {'2H': 5000},
        t1: [_foul('A', 1000), _foul('B', 6000)],
      ));
      await t.pumpWidget(_header(m));
      expect(find.text('2nd half'), findsOneWidget);
      expect(find.text('Fouls 1'), findsOneWidget);
      expect(find.text('Fouls 0'), findsOneWidget);
    });

    testWidgets('extra time label', (t) async {
      final m = _m(_game(period: 'ET', starts: {'2H': 5000, 'ET': 9000}));
      await t.pumpWidget(_header(m));
      expect(find.text('Extra time'), findsOneWidget);
    });

    testWidgets('final game shows nothing', (t) async {
      final m = _m(_game(status: 2, t1: [_foul('A', 1000)]));
      await t.pumpWidget(_header(m));
      expect(find.text('1st half'), findsNothing);
      expect(find.textContaining('Fouls'), findsNothing);
    });

    testWidgets('upcoming game shows nothing', (t) async {
      await t.pumpWidget(_header(_m(_game(status: 0))));
      expect(find.textContaining('Fouls'), findsNothing);
    });

    testWidgets('game without Period is exactly as today', (t) async {
      await t.pumpWidget(_header(_m(_game(period: null))));
      expect(find.byKey(const ValueKey('futsal_half_label')), findsNothing);
      expect(find.textContaining('Fouls'), findsNothing);
    });

    testWidgets('basketball game unchanged', (t) async {
      await t.pumpWidget(_header(_m(_game(), sport: 'Basketball')));
      expect(find.textContaining('Fouls'), findsNothing);
      expect(find.text('1st half'), findsNothing);
    });

    for (final dark in [false, true]) {
      testWidgets('360 px no overflow (dark=$dark)', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final m = _m(_game(period: 'HT', t1: [_foul('A', 1)]));
        await t.pumpWidget(_header(m, dark: dark));
        expect(t.takeException(), isNull);
      });
    }
  });

  testWidgets('timeline shows only real events with Period/ManDown present',
      (t) async {
    Future<List<String>> texts(Map<dynamic, dynamic> raw) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MatchFactsTab(
            match: _m(raw),
            team1: leagueTeamStub('Nineveh', null),
            team2: leagueTeamStub('Babylon', null),
            team1Players: const [],
            team2Players: const [],
            leagueSportKey: 'Futsal',
          ),
        ),
      ));
      return t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .toList();
    }

    final plain = _game(period: null, t1: [
      {'Goal': 'Ashur', '_t': 1000},
    ]);
    final withHalves = _game(period: '2H', starts: {
      '2H': 5000
    }, t1: [
      {'Goal': 'Ashur', '_t': 1000},
    ]);
    withHalves['ManDown'] = {
      'abc': {
        'Team': 1,
        'Reason': 'Red',
        'Player': 'Ashur',
        'DurationMs': 120000,
        'StartElapsedMs': 0,
      },
    };
    expect(await texts(withHalves), await texts(plain));
  });
}
