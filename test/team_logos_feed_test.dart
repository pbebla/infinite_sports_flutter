// S16 Task 1: team logos refresh on existing installs. `Logo Urls` used to
// be read once (from the phone's saved copy) and memoised for the session,
// so crests added after install (Futsal Season 16) stayed blank shields.
// Now ONE live subscription replaces `teamLogos` on every event and bumps
// `teamLogosVersion`; league crest widgets repaint from it.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/team_logos.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';

const _s16Url = 'https://example.com/futsal16/lions.png';

final Map _oldCopy = {
  'Futsal': {
    '15': {'Lions': 'https://example.com/futsal15/lions.png'},
  },
  'AFC San Jose': 'https://example.com/afc.png',
};

final Map _newCopy = {
  'Futsal': {
    '15': {'Lions': 'https://example.com/futsal15/lions.png'},
    '16': {'Lions': _s16Url, 'Tigers': 'https://example.com/futsal16/t.png'},
  },
  'AFC San Jose': 'https://example.com/afc.png',
};

const _match = TournamentMatch(
  id: 'm1',
  stage: 'Group Stage',
  label: 'Group Stage',
  date: '01102027',
  time: '7:00PM',
  team1Id: 'Lions',
  team2Id: 'Tigers',
  team1Score: 0,
  team2Score: 0,
  status: 0,
  bracketPosition: 0,
);

/// A league crest screen in miniature: the Season 16 fixtures list fed by
/// [watchSeasonLogos] exactly as the league screens are.
class _CrestHost extends StatefulWidget {
  const _CrestHost();
  @override
  State<_CrestHost> createState() => _CrestHostState();
}

class _CrestHostState extends State<_CrestHost> {
  Map<String, String> _logos = {};
  late final VoidCallback _stop;

  @override
  void initState() {
    super.initState();
    _stop = watchSeasonLogos('Futsal', '16', (logos) {
      if (mounted) setState(() => _logos = logos);
    });
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teams = leagueTeamsById(const [], _logos);
    for (final n in ['Lions', 'Tigers']) {
      teams.putIfAbsent(n, () => leagueTeamStub(n, null));
    }
    return FixturesTab(
      matches: const [_match],
      teams: teams,
      rosters: const {},
      tournamentId: '',
      sport: 'Futsal',
    );
  }
}

void main() {
  late List<String> logs;
  late DebugPrintCallback original;

  setUp(() {
    logs = [];
    original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
    TeamLogoFeed.debugReset();
  });

  tearDown(() {
    TeamLogoFeed.debugReset();
    debugPrint = original;
  });

  Iterable<String> imageUrls(WidgetTester tester) => tester
      .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
      .map((i) => i.imageUrl);

  testWidgets(
      'an old saved copy shows shields; the fresh copy fills the '
      'Season 16 crest in with no restart', (tester) async {
    final source = StreamController<Map>();
    TeamLogoFeed.sourceOverride = () => source.stream;

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: _CrestHost()),
    ));
    source.add(_oldCopy);
    await tester.pump();
    await tester.pump();
    expect(imageUrls(tester), isNot(contains(_s16Url)));
    expect(find.byIcon(Icons.shield_outlined), findsWidgets);

    final versionBefore = teamLogosVersion.value;
    source.add(_newCopy);
    await tester.pump();
    await tester.pump();
    expect(teamLogosVersion.value, greaterThan(versionBefore));
    expect(imageUrls(tester), contains(_s16Url));
    expect(teamLogos['Futsal']['16']['Lions'], _s16Url);

    await tester.pumpWidget(const SizedBox());
    await source.close();
    // testWidgets checks debugPrint is restored before tearDown runs.
    debugPrint = original;
  });

  test('getAllTeamLogo resolves on the FIRST event (the saved copy)', () async {
    final source = StreamController<Map>();
    TeamLogoFeed.sourceOverride = () => source.stream;
    var done = false;
    final f = TeamLogoFeed.ensureStarted().then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    source.add(_oldCopy);
    await f;
    expect(done, isTrue);
    expect(teamLogos['AFC San Jose'], 'https://example.com/afc.png');
    // Later calls answer at once, and the subscription is shared.
    var subscriptions = 0;
    TeamLogoFeed.sourceOverride = () {
      subscriptions++;
      return const Stream.empty();
    };
    await TeamLogoFeed.ensureStarted();
    expect(subscriptions, 0);
    // A later event still replaces the map.
    source.add(_newCopy);
    await Future<void>.delayed(Duration.zero);
    expect(teamLogos['Futsal']['16']['Lions'], _s16Url);
    await source.close();
  });

  test('a source that errors leaves the map empty and never throws', () async {
    TeamLogoFeed.sourceOverride =
        () => Stream<Map>.error(StateError('permission denied'));
    await TeamLogoFeed.ensureStarted();
    expect(teamLogos, isEmpty);
    expect(logs.join('\n'), contains('Team logos'));
  });

  test('an error after a good copy keeps the good copy', () async {
    final source = StreamController<Map>();
    TeamLogoFeed.sourceOverride = () => source.stream;
    final f = TeamLogoFeed.ensureStarted();
    source.add(_newCopy);
    await f;
    source.addError(StateError('lost'));
    await Future<void>.delayed(Duration.zero);
    expect(teamLogos['Futsal']['16']['Lions'], _s16Url);
    await source.close();
  });

  test('a source that cannot even be created never throws', () async {
    TeamLogoFeed.sourceOverride = () => throw StateError('no Firebase app');
    await TeamLogoFeed.ensureStarted();
    expect(teamLogos, isEmpty);
  });

  test(
      'a source that never answers gives up after the bound (empty map, '
      'no exception) and a late answer still fills in', () async {
    final source = StreamController<Map>();
    TeamLogoFeed.sourceOverride = () => source.stream;
    TeamLogoFeed.firstEventTimeout = const Duration(milliseconds: 20);
    await TeamLogoFeed.ensureStarted();
    expect(teamLogos, isEmpty);
    expect(logs.join('\n'), contains('Team logos: no answer'));
    // The next caller does not wait the bound again.
    final sw = Stopwatch()..start();
    await TeamLogoFeed.ensureStarted();
    expect(sw.elapsedMilliseconds, lessThan(15));
    source.add(_newCopy);
    await Future<void>.delayed(Duration.zero);
    expect(teamLogos['Futsal']['16']['Lions'], _s16Url);
    await source.close();
  });

  test('the production bound is the reveal-read convention (8 s)', () {
    expect(TeamLogoFeed.firstEventTimeout, const Duration(seconds: 8));
  });

  test('seasonLogoUrlsFrom reads teamLogos[sport][season] as strings', () {
    expect(seasonLogoUrlsFrom(_newCopy, 'Futsal', '16'),
        {'Lions': _s16Url, 'Tigers': 'https://example.com/futsal16/t.png'});
    expect(seasonLogoUrlsFrom(_newCopy, 'Futsal', '9'), isEmpty);
    expect(seasonLogoUrlsFrom(_newCopy, 'AFC San Jose', '1'), isEmpty);
    expect(seasonLogoUrlsFrom(const {}, 'Futsal', '16'), isEmpty);
  });

  test('watchSeasonLogos only reports real changes and stops on dispose',
      () async {
    final source = StreamController<Map>();
    TeamLogoFeed.sourceOverride = () => source.stream;
    final seen = <Map<String, String>>[];
    final stop = watchSeasonLogos('Futsal', '16', seen.add);
    source.add(_newCopy);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
    source.add(Map.of(_newCopy)); // same content: no repaint
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
    stop();
    source.add({
      'Futsal': {
        '16': {'Lions': 'x'}
      }
    });
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
    await source.close();
  });
}
