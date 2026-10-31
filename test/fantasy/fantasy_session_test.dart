// Sign-out hygiene: clearFantasySessionState() must forget every static
// fantasy session cache. The regression guard scans lib/ for any
// `static void clearSessionCache(s)` and for the remembered-UI statics,
// and fails when one is NOT reached from fantasy_session.dart — so a
// future round that adds a cache has to wire it here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_session.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/players_tab.dart';
import 'package:infinite_sports_flutter/fantasy/match/match_fantasy_tab.dart';

void main() {
  test('clearFantasySessionState resets the remembered UI state', () {
    FantasyPlayersTab.sessionSort = MarketSort.ownership;
    FantasyPlayersTab.sessionDescending = false;
    FantasyLeaderboardsTab.sessionScope = LeaderboardScope.teamOfWeek;
    FantasyLeaderboardsTab.sessionWeek = 7;
    DreamTeamCard.sessionWeek = 7;
    MatchFantasyTab.sessionEarnings['g1'] = 12;

    clearFantasySessionState();

    expect(FantasyPlayersTab.sessionSort, MarketSort.points);
    expect(FantasyPlayersTab.sessionDescending, isTrue);
    expect(FantasyLeaderboardsTab.sessionScope, LeaderboardScope.overall);
    expect(FantasyLeaderboardsTab.sessionWeek, isNull);
    expect(FantasyLeaderboardsTab.profilesSession, isNull);
    expect(DreamTeamCard.sessionWeek, isNull);
    expect(MatchFantasyTab.sessionEarnings, isEmpty);
  });

  test('every static session cache in lib/ is reached from fantasy_session',
      () {
    final session = File('lib/fantasy/data/fantasy_session.dart')
        .readAsStringSync();
    final reached = RegExp(r'(\w+)\.clearSessionCaches?\(\)')
        .allMatches(session)
        .map((m) => m.group(1)!)
        .toSet();
    // Feeds cleared transitively by the screens' own clears.
    final transitive = {
      'FantasyScheduleFeed',
      'FantasyLeagueGamesFeed',
      'FantasySeasonFinishedFeed',
    };

    final missing = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      if (!RegExp(r'static void clearSessionCaches?\(').hasMatch(src)) {
        continue;
      }
      for (final m in RegExp(r'class (\w+)').allMatches(src)) {
        final cls = m.group(1)!;
        final body = src.substring(m.start);
        final next = RegExp(r'\nclass ').firstMatch(body.substring(1));
        final scope = next == null ? body : body.substring(0, next.start + 1);
        if (!RegExp(r'static void clearSessionCaches?\(').hasMatch(scope)) {
          continue;
        }
        if (!reached.contains(cls) && !transitive.contains(cls)) {
          missing.add('$cls (${f.path})');
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'wire these into clearFantasySessionState(): $missing');
  });
}
