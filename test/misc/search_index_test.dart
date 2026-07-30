import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/search_index.dart';
import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/model/myuser.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';

void main() {
  SearchIndex build() {
    final index = SearchIndex();
    index.addTeamsAndLeagues({
      'Futsal': {
        '1': {'FC Barca': 'http://logo/barca1.png'},
        '2': {'FC Barca': 'http://logo/barca2.png', 'Inter': 'http://logo/inter.png'},
      },
      'AFC San Jose': 'http://logo/afc.png',
    });
    index.addTournaments([
      const Tournament(id: 't1', name: 'Summer Cup', sport: 'Soccer', edition: '2026', status: 'Live', finished: false),
    ]);
    index.addUsers({
      'uid1': MyUser('Zaya', 'Arami', '01012020', 'uid1'),
    });
    final e = Event();
    e.title = 'Futsal Finals Night';
    e.location = 'San Jose';
    index.addEvents([e]);
    return index;
  }

  test('finds teams case-insensitively, newest season wins, deduped', () {
    final hits = build().query('barca');
    expect(hits.length, 1);
    expect(hits.single.type, SearchResultType.team);
    expect(hits.single.season, '2');
  });

  test('skips the AFC San Jose string entry without crashing', () {
    expect(() => build().query('afc'), returnsNormally);
  });

  test('results are grouped in type order', () {
    final hits = build().query('u');
    final typeIndexes = hits.map((h) => h.type.index).toList();
    final sorted = [...typeIndexes]..sort();
    expect(typeIndexes, sorted, reason: 'results must be grouped in enum order');
  });

  test('player results carry the uid', () {
    final hits = build().query('zaya');
    expect(hits.single.type, SearchResultType.player);
    expect(hits.single.uid, 'uid1');
  });

  test('event results carry the original list index', () {
    final hits = build().query('finals');
    expect(hits.single.type, SearchResultType.event);
    expect(hits.single.eventIndex, 0);
  });

  test('empty query returns nothing', () {
    expect(build().query('  '), isEmpty);
  });
}
