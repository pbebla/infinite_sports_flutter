// Widget tests for the Help & Feedback form
// (lib/support/support_form_page.dart, zaya-support). Firebase-free: every
// prefill* seam is supplied so FirebaseAuth/FirebaseDatabase/package_info
// are never touched, submitOverride replaces the real
// SupportService.createTicket, pickImagesOverride replaces image_picker,
// and myTicketsPageBuilder replaces the real MyTicketsPage — the
// insiders_info_page_test.dart pattern.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:infinite_sports_flutter/support/support_form_page.dart';
import 'package:infinite_sports_flutter/support/support_models.dart';
import 'package:infinite_sports_flutter/support/support_service.dart';

/// The form is taller than the 800x600 test surface — scroll targets into
/// view before tapping (mirrors test/insiders_info_page_test.dart).
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

SupportFormPage _page({
  String fromScreen = 'Drawer',
  Future<int> Function({
    required String category,
    required String message,
    required List<XFile> screenshots,
    required String name,
    required String email,
    required String uid,
    required String appVersion,
    required String platform,
    required String device,
    required String screen,
  })? submitOverride,
  Future<List<XFile>> Function()? pickImagesOverride,
  Widget Function()? myTicketsPageBuilder,
}) {
  return SupportFormPage(
    fromScreen: fromScreen,
    prefillName: 'Zaya Arami',
    prefillEmail: 'zaya@example.com',
    prefillUid: 'uid123',
    prefillAppVersion: '3.0.0+10',
    prefillPlatform: 'Android',
    prefillDevice: 'android 14',
    submitOverride: submitOverride,
    pickImagesOverride: pickImagesOverride,
    myTicketsPageBuilder: myTicketsPageBuilder,
  );
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  bool submitEnabled(WidgetTester tester) {
    final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('support_submit_button')));
    return button.onPressed != null;
  }

  testWidgets('renders title, subtitle, all six category cards and the footer',
      (tester) async {
    await tester.pumpWidget(wrap(_page(
        submitOverride: ({
      required category,
      required message,
      required screenshots,
      required name,
      required email,
      required uid,
      required appVersion,
      required platform,
      required device,
      required screen,
    }) async =>
            1)));
    await tester.pump();

    expect(find.text('Support & feedback'), findsOneWidget);
    expect(
        find.text(
            'Tell us what you need — or what Infinite Sports should do next.'),
        findsOneWidget);
    for (final cat in kSupportCategories) {
      expect(find.byKey(ValueKey('support_cat_${cat.key}')), findsOneWidget);
      expect(find.text(cat.title), findsOneWidget);
    }
    expect(
        find.textContaining(
            "We'll include your name, email, app version and the screen"),
        findsOneWidget);
  });

  testWidgets('submit stays gated until BOTH a category and a message exist',
      (tester) async {
    await tester.pumpWidget(wrap(_page(
        submitOverride: ({
      required category,
      required message,
      required screenshots,
      required name,
      required email,
      required uid,
      required appVersion,
      required platform,
      required device,
      required screen,
    }) async =>
            1)));
    await tester.pump();

    // Nothing selected, nothing typed.
    expect(submitEnabled(tester), isFalse);

    // Category only — still gated.
    await _tapVisible(tester, find.byKey(const ValueKey('support_cat_bug')));
    await tester.pump();
    expect(submitEnabled(tester), isFalse);

    // Message too — enabled.
    await tester.ensureVisible(
        find.byKey(const ValueKey('support_message_field')));
    await tester.enterText(
        find.byKey(const ValueKey('support_message_field')), 'It broke.');
    await tester.pump();
    expect(submitEnabled(tester), isTrue);

    // Whitespace-only message — gated again.
    await tester.enterText(
        find.byKey(const ValueKey('support_message_field')), '   ');
    await tester.pump();
    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('message field caps at 5000 characters', (tester) async {
    await tester.pumpWidget(wrap(_page()));
    await tester.pump();

    final field = tester.widget<TextField>(
        find.byKey(const ValueKey('support_message_field')));
    expect(field.maxLength, kSupportMessageMaxLength);

    await tester.ensureVisible(
        find.byKey(const ValueKey('support_message_field')));
    await tester.enterText(find.byKey(const ValueKey('support_message_field')),
        'a' * (kSupportMessageMaxLength + 100));
    await tester.pump();
    expect(field.controller!.text.length, kSupportMessageMaxLength);
  });

  testWidgets('screenshot picks cap at 5 thumbnails and hide the add button',
      (tester) async {
    final picked = [for (var i = 0; i < 7; i++) XFile('missing_$i.jpg')];
    await tester.pumpWidget(wrap(_page(pickImagesOverride: () async => picked)));
    await tester.pump();

    await _tapVisible(
        tester, find.byKey(const ValueKey('support_add_screenshot_button')));
    await tester.pump();
    await tester.pump();

    // 5 kept (each with its remove ✕), the 2 extras dropped, add button gone.
    for (var i = 0; i < kMaxScreenshots; i++) {
      expect(find.byKey(ValueKey('support_shot_remove_$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('support_shot_remove_5')), findsNothing);
    expect(find.byKey(const ValueKey('support_add_screenshot_button')),
        findsNothing);
    expect(find.textContaining('the extras were left out'), findsOneWidget);

    // Removing one brings the add button back.
    await _tapVisible(
        tester, find.byKey(const ValueKey('support_shot_remove_0')));
    await tester.pump();
    expect(find.byKey(const ValueKey('support_add_screenshot_button')),
        findsOneWidget);
  });

  testWidgets(
      'submit passes the fully assembled context through submitOverride and '
      'the success body shows the reference number', (tester) async {
    Map<String, Object?>? captured;
    await tester.pumpWidget(wrap(_page(
      fromScreen: 'Settings',
      pickImagesOverride: () async => [XFile('shot.jpg')],
      submitOverride: ({
        required category,
        required message,
        required screenshots,
        required name,
        required email,
        required uid,
        required appVersion,
        required platform,
        required device,
        required screen,
      }) async {
        captured = {
          'category': category,
          'message': message,
          'screenshots': screenshots.length,
          'name': name,
          'email': email,
          'uid': uid,
          'appVersion': appVersion,
          'platform': platform,
          'device': device,
          'screen': screen,
        };
        return 42;
      },
      myTicketsPageBuilder: () =>
          const Scaffold(body: Center(child: Text('stub tickets'))),
    )));
    await tester.pump();

    await _tapVisible(
        tester, find.byKey(const ValueKey('support_cat_suggestion')));
    await tester.ensureVisible(
        find.byKey(const ValueKey('support_message_field')));
    await tester.enterText(find.byKey(const ValueKey('support_message_field')),
        '  Add a schedule widget.  ');
    await _tapVisible(
        tester, find.byKey(const ValueKey('support_add_screenshot_button')));
    await tester.pump();
    await _tapVisible(
        tester, find.byKey(const ValueKey('support_submit_button')));
    await tester.pump();
    await tester.pump();

    expect(captured, {
      'category': 'suggestion',
      'message': 'Add a schedule widget.', // trimmed
      'screenshots': 1,
      'name': 'Zaya Arami',
      'email': 'zaya@example.com',
      'uid': 'uid123',
      'appVersion': '3.0.0+10',
      'platform': 'Android',
      'device': 'android 14',
      'screen': 'Settings',
    });

    // Success body replaces the form.
    expect(find.byKey(const ValueKey('support_success')), findsOneWidget);
    expect(find.text('Thanks — your reference is #42'), findsOneWidget);
    expect(find.byKey(const ValueKey('support_submit_button')), findsNothing);

    // "View my tickets" pushes the (stubbed) tickets page.
    await _tapVisible(
        tester, find.byKey(const ValueKey('support_view_tickets_button')));
    await tester.pumpAndSettle();
    expect(find.text('stub tickets'), findsOneWidget);
  });

  testWidgets('rate-limit exception surfaces its friendly message',
      (tester) async {
    await tester.pumpWidget(wrap(_page(
      submitOverride: ({
        required category,
        required message,
        required screenshots,
        required name,
        required email,
        required uid,
        required appVersion,
        required platform,
        required device,
        required screen,
      }) async =>
          throw const SupportRateLimitException(),
    )));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const ValueKey('support_cat_help')));
    await tester.ensureVisible(
        find.byKey(const ValueKey('support_message_field')));
    await tester.enterText(
        find.byKey(const ValueKey('support_message_field')), 'How do I…?');
    await _tapVisible(
        tester, find.byKey(const ValueKey('support_submit_button')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('give it a little time'), findsOneWidget);
    // Still on the form — no success body.
    expect(find.byKey(const ValueKey('support_success')), findsNothing);
  });

  testWidgets('app-bar tickets icon opens the (stubbed) My Tickets page',
      (tester) async {
    await tester.pumpWidget(wrap(_page(
      myTicketsPageBuilder: () =>
          const Scaffold(body: Center(child: Text('stub tickets'))),
    )));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('support_my_tickets_button')));
    await tester.pumpAndSettle();
    expect(find.text('stub tickets'), findsOneWidget);
  });
}
