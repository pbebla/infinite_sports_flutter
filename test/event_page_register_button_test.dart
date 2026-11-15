// "My registration" way back: on an event with a registration, a fan who
// already registered sees "View my registration" (open OR closed) instead of
// Register; everyone else sees Register. Firebase-free via the seams.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/live_registration_config.dart';
import 'package:infinite_sports_flutter/registration/registration_open.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';

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
    ..registrationId = 'Futsal-16';
  return e;
}

void main() {
  Future<void> pump(WidgetTester tester, Stream<RegSubmission?> mine,
      {ThemeMode mode = ThemeMode.light}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      themeMode: mode,
      home: EventPage(
        index: 0,
        eventStream: Stream<Event?>.value(_event()),
        loadUsers: () async => {},
        mySubmissionFor: (regId) {
          expect(regId, 'Futsal-16');
          return mine;
        },
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('${mode.name} 360 px: registered -> View my registration',
        (tester) async {
      await pump(tester,
          Stream.value(const RegSubmission(path: 'individual', answers: {})),
          mode: mode);
      expect(tester.takeException(), isNull);
      expect(find.text('View my registration'), findsOneWidget);
      expect(find.text('Register'), findsNothing);
    });
  }

  testWidgets('not registered -> Register', (tester) async {
    await pump(tester, Stream.value(null));
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('View my registration'), findsNothing);
  });

  testWidgets(
      'a failed own-submission read never guesses: Register, and '
      'the tap decides (couldn\'t-check there)', (tester) async {
    await pump(tester, Stream<RegSubmission?>.error(StateError('denied')));
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Registration is closed'), findsNothing);
  });

  testWidgets('the label follows a submission that appears live',
      (tester) async {
    final mine = StreamController<RegSubmission?>();
    await pump(tester, mine.stream);
    mine.add(null);
    await tester.pump();
    expect(find.text('Register'), findsOneWidget);
    mine.add(const RegSubmission(path: 'captain', answers: {}));
    await tester.pump();
    expect(find.text('View my registration'), findsOneWidget);
    await mine.close();
  });

  // Final small round, N7: the event page's Register goes through the shared
  // RegistrationOpen path, so "couldn't check" has a Try again (kept behind
  // the page's own spinner and one-tap guard).
  testWidgets('couldn\'t check offers Try again, which then opens once',
      (tester) async {
    const config = RegistrationConfig(
      targetType: 'league',
      sport: 'Futsal',
      season: '16',
      status: 'open',
      fee: 60,
      paymentMode: 'perPlayer',
    );
    final answers = [
      (route: RegistrationRoute.couldNotCheck, config: null),
      (route: RegistrationRoute.register, config: config),
    ];
    var checks = 0;
    final opened = <String>[];
    RegistrationOpen.checkOverride = (regId) async => answers[checks++];
    RegistrationOpen.pathPageOverride = (regId, c) {
      opened.add('path:$regId');
      return const Scaffold(body: Text('path page'));
    };
    addTearDown(() {
      RegistrationOpen.checkOverride = null;
      RegistrationOpen.pathPageOverride = null;
    });
    await pump(tester, Stream.value(null));
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(find.text(kRegistrationCouldNotCheck), findsOneWidget);
    expect(opened, isEmpty);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(checks, 2);
    expect(opened, ['path:Futsal-16']);
  });
}
