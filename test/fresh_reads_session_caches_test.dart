// Fresh reads, Task 4 — the session caches of survey list B are refilled or
// dropped when a lingering refreshing read reports a newer server value
// (FreshReads.debugReportNewer stands in for that report).

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/misc/app_config.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';
import 'package:infinite_sports_flutter/misc/public_profiles.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/profile/profile_page.dart';

void main() {
  test('lineups caches are re-parsed in place and bump lineupsVersion', () {
    followLineUps();
    final v0 = lineupsVersion.value;
    FreshReads.debugReportNewer('/Futsal/16/Line Ups', {
      'Lions': {
        'Bruno': {'Goals': 7, 'Assists': 1, 'Saves': 0, 'number': '9'},
      },
    });
    expect(futsalLineups['16']!['Lions']!['Bruno']!.goals, 7);
    expect(lineupsVersion.value, v0 + 1);
    FreshReads.debugReportNewer('Basketball/4/Line Ups', {
      'Hawks': {
        'Ana': {'OnePoint': 1, 'TwoPoints': 2, 'ThreePoints': 0},
      },
    });
    expect(basketballLineups['4']!['Hawks']!['Ana']!.total, 5);
    // Not a lineups node: untouched.
    FreshReads.debugReportNewer('Futsal/16/Teams', {'x': 1});
    expect(lineupsVersion.value, v0 + 2);
    // A malformed newer value keeps the cache.
    FreshReads.debugReportNewer('Futsal/16/Line Ups', 'junk');
    expect(futsalLineups['16']!['Lions']!['Bruno']!.goals, 7);
  });

  test('roster-photo caches take newer ProfileUrls (one uid or the mirror)',
      () {
    final cache = {'u1': 'old.png', 'u2': ''};
    final stop = followProfileUrlCache(cache);
    FreshReads.debugReportNewer('PublicProfiles/u1/ProfileUrl', 'new.png');
    FreshReads.debugReportNewer('PublicProfiles/u9/ProfileUrl', 'x.png');
    expect(cache, {'u1': 'new.png', 'u2': ''});
    FreshReads.debugReportNewer('PublicProfiles', {
      'u2': {'ProfileUrl': 'two.png'},
    });
    expect(cache, {'u1': '', 'u2': 'two.png'});
    stop();
    FreshReads.debugReportNewer('PublicProfiles/u1/ProfileUrl', 'later.png');
    expect(cache['u1'], '');
  });

  test('store links are refilled from a newer value', () async {
    debugResetStoreLinks();
    addTearDown(() {
      FreshReads.refreshingValueOverride = null;
      debugResetStoreLinks();
    });
    FreshReads.refreshingValueOverride =
        (_) async => {'Android': 'https://old'};
    expect((await getStoreLinks()).android, 'https://old');
    FreshReads.debugReportNewer('AppConfig/StoreLinks', {
      'Android': 'https://new',
      'iOS': 'https://ios',
    });
    FreshReads.refreshingValueOverride = (_) async => fail('no re-read');
    final links = await getStoreLinks();
    expect(links.android, 'https://new');
    expect(links.ios, 'https://ios');
  });

  test("a newer Start Time drops that season's memoised kick-off hour", () {
    FantasyLeagueGamesFeed.debugSetStartHour('Futsal', '16', 19);
    FantasyLeagueGamesFeed.debugSetStartHour('Futsal', '15', 18);
    FreshReads.debugReportNewer('/Futsal/16/Start Time', '7:00PM');
    expect(FantasyLeagueGamesFeed.debugHasStartHour('Futsal', '16'), isFalse);
    expect(FantasyLeagueGamesFeed.debugHasStartHour('Futsal', '15'), isTrue);
    FantasyLeagueGamesFeed.clearSessionCache();
  });

  test('a newer PublicProfiles mirror drops the fantasy names cache', () {
    FantasyLeaderboardsTab.profilesSessionFollow;
    FantasyLeaderboardsTab.profilesSession = Future.value({});
    FreshReads.debugReportNewer('PublicProfiles', {'u1': {}});
    expect(FantasyLeaderboardsTab.profilesSession, isNull);
  });

  test(
      'which newer values affect a career: only what it read (second '
      'review, Important 1)', () {
    const reads = {
      'PublicProfiles/u1',
      'PublicProfiles/u1/TournamentsPlayed',
      'Futsal/16/Line Ups/Lions',
      'AFC San Jose/Seasons/S1/Roster',
      'Tournaments/t1',
    };
    bool hit(String p) => ProfilePage.careerReadsAffected(reads, p);
    expect(hit('Futsal/16/Line Ups/Lions'), isTrue);
    expect(hit('Futsal/16/Line Ups'), isTrue, reason: 'an ancestor changed');
    expect(hit('Tournaments/t1/Matches/m1'), isTrue, reason: 'below a read');
    expect(hit('PublicProfiles/u1'), isTrue);
    expect(hit('Futsal/16/Line Ups/Tigers'), isFalse, reason: 'another team');
    expect(hit('Basketball/4/Line Ups/Hawks'), isFalse);
    expect(hit('Tournaments/t2'), isFalse);
    expect(hit('PublicProfiles/u2'), isFalse);
    expect(hit('Logo Urls'), isFalse);
  });
}
