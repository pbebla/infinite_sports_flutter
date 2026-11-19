// Release report #11: the same player was shown as "Attacker", "ATT" and
// "Striker". Those are TWO concepts, kept apart on purpose (owner decision):
//   1. the player's own playing position from registration (as stored —
//      "Goal Keeper" / "Defender" / "Midfielder" / "Striker"), normalised by
//      formatPlayingPosition / playingPositionLabel;
//   2. the Infinite Fantasy position group, from FantasyPosition's display
//      getters: GK / DEF / ATT for chips and cells, Goalkeeper / Defender /
//      Attacker where a full word is spelled out, "Fantasy: ATT" outside the
//      hub.
// Display strings only — the stored keys (FantasyPosition.db) never change.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/misc/playing_position.dart';
import 'package:infinite_sports_flutter/model/award.dart';
import 'package:infinite_sports_flutter/profile/profile_tab.dart';
import 'package:infinite_sports_flutter/misc/profile_stat_priority.dart';

void main() {
  group('fantasy position group — one vocabulary', () {
    test('short codes for chips / filters / cells', () {
      expect(FantasyPosition.values.map((p) => p.short), ['GK', 'DEF', 'ATT']);
    });

    test('long form where a word is spelled out', () {
      expect(FantasyPosition.values.map((p) => p.long),
          ['Goalkeeper', 'Defender', 'Attacker']);
      expect(FantasyPosition.values.map((p) => p.longPlural),
          ['Goalkeepers', 'Defenders', 'Attackers']);
    });

    test('sentence forms are the same words, lower case', () {
      expect(FantasyPosition.values.map((p) => p.noun),
          ['goalkeeper', 'defender', 'attacker']);
      expect(FantasyPosition.values.map((p) => p.nounPlural),
          ['goalkeepers', 'defenders', 'attackers']);
      expect(FantasyPosition.values.map((p) => p.withArticle),
          ['a goalkeeper', 'a defender', 'an attacker']);
      expect(FantasyPosition.gk.count(1), '1 goalkeeper');
      expect(FantasyPosition.def.count(2), '2 defenders');
    });

    test('outside the hub it is labelled "Fantasy: ATT"', () {
      expect(FantasyPosition.att.fantasyTag, 'Fantasy: ATT');
    });

    test('the stored key is untouched', () {
      expect(FantasyPosition.values.map((p) => p.db), ['GK', 'DEF', 'ATT']);
    });
  });

  group('playing position — registration words as stored', () {
    test('capitalisation only; never translated into a fantasy group', () {
      expect(formatPlayingPosition('striker'), 'Striker');
      expect(formatPlayingPosition('Goal Keeper'), 'Goal Keeper');
      expect(formatPlayingPosition('point guard'), 'Point Guard');
      expect(formatPlayingPosition('GK'), 'GK');
      expect(formatPlayingPosition('QB'), 'QB');
    });

    test('a multi-select list reads "Defender · Striker"', () {
      expect(formatPlayingPosition('Defender;Striker'), 'Defender · Striker');
      expect(formatPlayingPosition(' Defender ; ;striker;Defender '),
          'Defender · Striker');
      expect(formatPlayingPosition('Defender, Midfielder'),
          'Defender · Midfielder');
    });

    test('blank is blank', () {
      expect(formatPlayingPosition(''), '');
      expect(formatPlayingPosition(' ; '), '');
      expect(playingPositionLabel(''), '');
    });

    test('labelled "Position:" (one) / "Positions:" (several)', () {
      expect(playingPositionLabel('Striker'), 'Position: Striker');
      expect(playingPositionLabel('Defender;Striker'),
          'Positions: Defender · Striker');
    });
  });

  testWidgets(
      'the profile\'s team card says "Position: Defender · Striker" '
      '— never the fantasy group', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProfileTab(
          uid: 'uid_alice',
          information: const {},
          awards: const <Award>[],
          current: ParticipationStint(
            sport: 'Futsal',
            label: '15',
            sortKey: 15,
            team: 'Nimrod',
            position: 'Defender;striker',
            isActive: false,
          ),
          currentTeamNumber: '9',
          insiderStream: const Stream.empty(),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Positions: Defender · Striker'), findsOneWidget);
    expect(find.text('#9'), findsOneWidget);
    expect(find.textContaining('Fantasy'), findsNothing);
    expect(find.textContaining('ATT'), findsNothing);
  });
}
