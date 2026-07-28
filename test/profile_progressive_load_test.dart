// Progressive profile loading (perf): phase 1 (identity) gates the first
// paint; phase 2 (career) fills the career-dependent sections in place via
// setState. Covered here:
//   1. hero + tabs render as soon as phase 1 resolves, with skeleton
//      placeholders in the career sections while phase 2 is in flight,
//   2. phase 2 completing swaps the placeholders for real content in place,
//   3. loadOverride alone (the existing seam) still resolves the full page
//      at once — no skeletons after the future completes.
// Firebase-free: loadOverride resolves phase 1; the careerLoadOverride seam
// (mirrors loadOverride) holds phase 2 open until the test releases it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/profile/profile_hero.dart';
import 'package:infinite_sports_flutter/profile/profile_page.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

void main() {
  testWidgets('hero renders while career sections are still loading',
      (tester) async {
    final career = Completer<void>();
    // Empty uid keeps ProfileTab's Insider box (the only other Firebase
    // touchpoint) dormant.
    await tester.pumpWidget(MaterialApp(
      home: ProfilePage(
        uid: '',
        loadOverride: () async => 1,
        careerLoadOverride: () => career.future,
      ),
    ));
    await tester.pump(); // skeleton frame
    await tester.pump(); // phase 1 resolved → hero + tabs

    // Identity is up...
    expect(find.byType(ProfileHero), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Profile'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Career'), findsOneWidget);
    // ...but the Current Team card still shows a placeholder, not a verdict.
    expect(find.byType(SkeletonBox), findsWidgets);
    expect(find.text('Not currently on a roster.'), findsNothing);

    // Phase 2 landing fills the section in place.
    career.complete();
    await tester.pump();
    expect(find.byType(SkeletonBox), findsNothing);
    expect(find.text('Not currently on a roster.'), findsOneWidget);
  });

  testWidgets('loadOverride alone still resolves the full page',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProfilePage(uid: '', loadOverride: () async => 1),
    ));
    await tester.pump(); // skeleton frame
    await tester.pump(); // loadOverride resolved → full page, both phases

    expect(find.byType(ProfileHero), findsOneWidget);
    expect(find.byType(SkeletonBox), findsNothing);
    expect(find.text('Not currently on a roster.'), findsOneWidget);
  });
}
