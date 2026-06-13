import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/widgets/live_filter_bar.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

TournamentMatch _m(int status) => TournamentMatch(
      id: 's$status', stage: 'Group Stage', label: 'Group Stage', date: '08272026',
      team1Score: 0, team2Score: 0, status: status, bracketPosition: 0,
    );

void main() {
  test('liveOnly keeps status==1 only', () {
    final all = [_m(0), _m(1), _m(2), _m(1)];
    expect(liveMatches(all).length, 2);
    expect(liveMatches(all).every((m) => m.status == 1), true);
  });
  test('liveMatches empty when none live', () {
    expect(liveMatches([_m(0), _m(2)]), isEmpty);
  });
}
