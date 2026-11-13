// "A slow first load of the player list is not 'nobody'": a timed-out or
// failed PublicProfiles read must be distinguishable from an empty mirror
// (null, not {}), and the screens that use it must say so / retry instead of
// showing no players or blank attendee names. Firebase-free via the
// rootReadOverride / load / loadUsers seams.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/misc/public_profiles.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/model/myuser.dart';
import 'package:infinite_sports_flutter/search_hub_page.dart';

Event _event() {
  final e = Event()
    ..title = 'Futsal Night'
    ..info = 'Come play'
    ..address = ''
    ..eventDate = 'September 27, 2026'
    ..startDate = DateTime(2026, 9, 27)
    ..eventDateTime = DateTime(2026, 9, 27)
    ..startTime = '6:00PM'
    ..endTime = '8:00PM'
    ..attendees = {'uid_alice': 'true'};
  return e;
}

void main() {
  tearDown(() => PublicProfiles.rootReadOverride = null);

  group('PublicProfiles.getAllOnceOrNull', () {
    test('a failed read is null, not an empty mirror', () async {
      PublicProfiles.rootReadOverride =
          () async => throw Exception('permission-denied');
      expect(await PublicProfiles.getAllOnceOrNull(), isNull);
      // The legacy {} contract (fantasy leaderboard) is unchanged.
      expect(await PublicProfiles.getAllOnce(), isEmpty);
    });

    testWidgets('a read with no answer after the bound is null',
        (tester) async {
      PublicProfiles.rootReadOverride = () => Completer<Object?>().future;
      Map<String, PublicProfile>? result = {};
      var done = false;
      PublicProfiles.getAllOnceOrNull().then((r) {
        result = r;
        done = true;
      });
      await tester.pump(const Duration(seconds: 9));
      expect(done, isTrue);
      expect(result, isNull);
    });

    test('an empty mirror is {} and a real one parses', () async {
      PublicProfiles.rootReadOverride = () async => null;
      expect(await PublicProfiles.getAllOnceOrNull(), isEmpty);
      PublicProfiles.rootReadOverride = () async => {
            'uid_alice': {'First Name': 'Alice', 'Last Name': 'Example'}
          };
      final got = await PublicProfiles.getAllOnceOrNull();
      expect(got!['uid_alice']!.fullName, 'Alice Example');
    });
  });

  group('getAllUsers', () {
    test('a failed profiles load is null, not {}', () async {
      expect(await getAllUsers(load: () async => null), isNull);
    });

    test('a loaded mirror maps to users', () async {
      final users = await getAllUsers(
          load: () async => {
                'uid_alice': const PublicProfile(
                    uid: 'uid_alice', firstName: 'Alice', lastName: 'Example')
              });
      expect(users!['uid_alice']!.firstName, 'Alice');
    });
  });

  group('event page attendees', () {
    testWidgets(
        'a failed users load says so, then retries on the next stream event',
        (tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final events = StreamController<Event?>();
      addTearDown(events.close);
      var calls = 0;
      final firstLoad = Completer<Map<String, MyUser>?>();
      await tester.pumpWidget(MaterialApp(
        home: EventPage(
          index: 0,
          eventStream: events.stream,
          loadUsers: () async {
            calls++;
            if (calls == 1) return firstLoad.future;
            return {'uid_alice': MyUser('Alice', 'Example', '', 'uid_alice')};
          },
        ),
      ));
      events.add(_event());
      await tester.pump();
      // Still waiting on names: the skeleton, not blank names.
      expect(find.text('Futsal Night'), findsNothing);

      firstLoad.complete(null); // the read failed / timed out
      await tester.pump();
      await tester.pump();

      expect(calls, 1);
      expect(find.text("Couldn't load attendees"), findsOneWidget);
      expect(find.text('Alice Example'), findsNothing);

      events.add(_event());
      await tester.pump();
      await tester.pump();

      expect(calls, 2);
      expect(find.text("Couldn't load attendees"), findsNothing);
      expect(find.text('Alice Example'), findsOneWidget);
    });
  });

  group('search hub players', () {
    testWidgets(
        'a failed player load rebuilds the player index on the next search',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
        home: SearchHubPage(
          fantasyGateOverride: const Stream.empty(),
          loadUsers: () async {
            calls++;
            if (calls == 1) return null;
            return {'uid_alice': MyUser('Alice', 'Example', '', 'uid_alice')};
          },
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(calls, 1);

      await tester.enterText(find.byType(TextField), 'Ali');
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump();
      expect(calls, 2);
      expect(find.text('Alice Example'), findsOneWidget);

      // Loaded now — later searches don't refetch.
      await tester.enterText(find.byType(TextField), 'Alic');
      await tester.pump();
      expect(calls, 2);
    });
  });
}
