// Sign-out hygiene for every static fantasy session cache (owner rule:
// session caches give instant revisits — but they must never outlive the
// user that filled them on a shared phone).
//
// Every fantasy screen and feed keeps app-lifetime statics (snapshots for
// the single fade reveal, remembered sort/scope/week, the match tab's
// earning tween memory). Each owns a `clearSessionCache(s)` for its own
// statics; this is the ONE place that calls them all, so the sign-out
// handler (navbar.dart) can't forget a cache that a later round adds —
// add the new class's clear here and the regression test in
// test/fantasy/fantasy_session_test.dart pins it.

import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/players_tab.dart';
import 'package:infinite_sports_flutter/fantasy/match/match_fantasy_tab.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_page.dart';
import 'package:infinite_sports_flutter/profile/fantasy_profile_source.dart';

/// Forgets everything fantasy remembered for the signed-in user: data
/// snapshots (service + feeds), remembered UI state (sort, scope, weeks),
/// the squad-viewer profile lookups and the match tab's earning memory.
void clearFantasySessionState() {
  FantasyService.clearSessionCaches();
  FantasyPlayersTab.clearSessionCaches(); // + games / start-hour / finished feeds
  FantasyPlayerProfilePage.clearSessionCaches(); // + schedule feed
  FantasyProfileSource.clearSessionCaches(); // + season resolution
  FantasyPlayersTab.sessionSort = MarketSort.points;
  FantasyPlayersTab.sessionDescending = true;
  FantasyLeaderboardsTab.sessionScope = LeaderboardScope.overall;
  FantasyLeaderboardsTab.sessionWeek = null;
  FantasyLeaderboardsTab.profilesSession = null;
  DreamTeamCard.sessionWeek = null;
  MatchFantasyTab.sessionEarnings.clear();
}
