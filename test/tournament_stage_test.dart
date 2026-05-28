import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournament_stage.dart';

void main() {
  group('TournamentStage', () {
    test('fromString recognizes group stage', () {
      expect(TournamentStage.fromString('Group Stage'), TournamentStage.group);
      expect(TournamentStage.fromString('group stage'), TournamentStage.group);
      expect(TournamentStage.fromString('GROUPS'), TournamentStage.group);
    });

    test('fromString recognizes round of 16', () {
      expect(TournamentStage.fromString('Round of 16'), TournamentStage.roundOf16);
      expect(TournamentStage.fromString('ro16'), TournamentStage.roundOf16);
      expect(TournamentStage.fromString('R16'), TournamentStage.roundOf16);
    });

    test('fromString recognizes quarterfinals', () {
      expect(TournamentStage.fromString('Quarterfinal'), TournamentStage.quarterFinal);
      expect(TournamentStage.fromString('QF'), TournamentStage.quarterFinal);
      expect(TournamentStage.fromString('quarter-final'), TournamentStage.quarterFinal);
    });

    test('fromString recognizes semifinals', () {
      expect(TournamentStage.fromString('Semifinal'), TournamentStage.semiFinal);
      expect(TournamentStage.fromString('SF'), TournamentStage.semiFinal);
    });

    test('fromString recognizes final', () {
      expect(TournamentStage.fromString('Final'), TournamentStage.finalStage);
      expect(TournamentStage.fromString('F'), TournamentStage.finalStage);
      expect(TournamentStage.fromString('Championship'), TournamentStage.finalStage);
    });

    test('fromString recognizes third place', () {
      expect(TournamentStage.fromString('Third Place'), TournamentStage.thirdPlace);
      expect(TournamentStage.fromString('3rd Place'), TournamentStage.thirdPlace);
    });

    test('fromString returns unknown for unrecognized', () {
      expect(TournamentStage.fromString('Mystery'), TournamentStage.unknown);
      expect(TournamentStage.fromString(''), TournamentStage.unknown);
      expect(TournamentStage.fromString(null), TournamentStage.unknown);
    });

    test('sortOrder orders stages chronologically', () {
      final stages = [
        TournamentStage.finalStage,
        TournamentStage.group,
        TournamentStage.thirdPlace,
        TournamentStage.semiFinal,
        TournamentStage.quarterFinal,
        TournamentStage.roundOf16,
      ];
      stages.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      expect(stages.first, TournamentStage.group);
      expect(stages.last, TournamentStage.finalStage);
    });

    test('isKnockout identifies knockout stages', () {
      expect(TournamentStage.group.isKnockout, false);
      expect(TournamentStage.roundOf16.isKnockout, true);
      expect(TournamentStage.quarterFinal.isKnockout, true);
      expect(TournamentStage.semiFinal.isKnockout, true);
      expect(TournamentStage.finalStage.isKnockout, true);
      expect(TournamentStage.thirdPlace.isKnockout, true);
      expect(TournamentStage.unknown.isKnockout, false);
    });
  });
}
