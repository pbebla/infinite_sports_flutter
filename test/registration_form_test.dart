import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/dynamic_form.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  final allTypes = <RegQuestion>[
    const RegQuestion(key: 'firstName', type: 'shortText', label: 'First Name'),
    const RegQuestion(key: 'bio', type: 'paragraph', label: 'About You'),
    const RegQuestion(key: 'age', type: 'number', label: 'Age'),
    const RegQuestion(key: 'phone', type: 'phone', label: 'Phone Number'),
    const RegQuestion(key: 'email', type: 'email', label: 'Email Address'),
    const RegQuestion(key: 'birthday', type: 'date', label: 'Birthday'),
    const RegQuestion(
        key: 'shirt', type: 'dropdown', label: 'Shirt Size', options: ['S', 'M', 'L']),
    const RegQuestion(
        key: 'foot',
        type: 'singleChoice',
        label: 'Preferred Foot',
        options: ['Left', 'Right']),
    const RegQuestion(
        key: 'positions',
        type: 'multiChoice',
        label: 'Positions',
        options: ['Defender', 'Striker']),
    const RegQuestion(key: 'played', type: 'yesNo', label: 'Played Before?'),
    const RegQuestion(key: 'height', type: 'height', label: 'Height'),
    const RegQuestion(
        key: 'waiver', type: 'linkAcknowledge', label: 'Waiver Conditions'),
  ];

  testWidgets('renders every question type', (tester) async {
    tester.view.physicalSize = const Size(1200, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(DynamicRegistrationForm(
      questions: allTypes,
      initialValues: const {},
      submitLabel: 'Register',
      onSubmit: (_) async {},
    )));
    await tester.pumpAndSettle();
    for (final q in allTypes) {
      expect(find.text(q.label), findsOneWidget,
          reason: 'missing field for type ${q.type}');
    }
    expect(find.text('Register'), findsOneWidget);
  });

  testWidgets('required text question gates submission; hygiene applied',
      (tester) async {
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(wrap(DynamicRegistrationForm(
      questions: const [
        RegQuestion(
            key: 'firstName',
            type: 'shortText',
            label: 'First Name',
            isRequired: true),
      ],
      initialValues: const {},
      submitLabel: 'Register',
      onSubmit: (a) async => submitted = a,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(submitted, isNull, reason: 'empty required field must block submit');

    await tester.enterText(find.byType(TextField).first, '  john   doe ');
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(submitted, isNotNull);
    expect(submitted!['firstName'], 'John Doe');
  });

  testWidgets('height renders feet+inches boxes and composes "6\'1"',
      (tester) async {
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(wrap(DynamicRegistrationForm(
      questions: const [
        RegQuestion(key: 'height', type: 'height', label: 'Height'),
      ],
      initialValues: const {},
      submitLabel: 'Register',
      onSubmit: (a) async => submitted = a,
    )));
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(2));

    await tester.enterText(textFields.at(0), '6');
    await tester.enterText(textFields.at(1), '1');
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!['height'], "6'1");
  });

  testWidgets('required linkAcknowledge blocks until opened', (tester) async {
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(wrap(DynamicRegistrationForm(
      questions: const [
        RegQuestion(
            key: 'waiver',
            type: 'linkAcknowledge',
            label: 'Waiver Conditions',
            isRequired: true),
      ],
      initialValues: const {},
      submitLabel: 'Register',
      onSubmit: (a) async => submitted = a,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(submitted, isNull, reason: 'unread acknowledgement must block');

    // Empty-hint acknowledge with a well-known key ('waiver'): the tile falls
    // back to the legacy RTDB lookup, which fails in this test environment
    // (no Firebase app — see the defensive try/catch in
    // _LinkAcknowledgeFieldState._resolveUrl), so it resolves to "no document
    // attached" and marks itself read on tap without opening a webview.
    await tester.tap(find.text('Waiver Conditions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(submitted, isNotNull);
    expect(submitted!['waiver'], true);
  });

  testWidgets(
      'linkAcknowledge with an unknown key and empty hint has nowhere to '
      'resolve a URL, so it still ticks (last-resort) on tap',
      (tester) async {
    await tester.pumpWidget(wrap(DynamicRegistrationForm(
      questions: const [
        RegQuestion(
            key: 'somethingElse',
            type: 'linkAcknowledge',
            label: 'Something Else'),
      ],
      initialValues: const {},
      submitLabel: 'Register',
      onSubmit: (_) async {},
    )));
    await tester.pumpAndSettle();

    // Not a well-known key ('rules'/'waiver') and no hint set: resolution has
    // nowhere to look, so it falls back to marking itself read (last resort)
    // instead of getting stuck.
    expect(find.text('Tap to open and read'), findsOneWidget);
    await tester.tap(find.text('Something Else'));
    await tester.pumpAndSettle();
    expect(find.text('Read — thank you!'), findsOneWidget);
  });

  testWidgets(
      'linkAcknowledge with a hint URL attempts navigation instead of '
      'ticking immediately', (tester) async {
    // webview_flutter has no platform implementation under `flutter test`
    // (WebViewController() throws without one registered), so this can't
    // render the pushed screen end-to-end here. What it does verify — the
    // regression this fix targets — is that a present hint URL is NOT
    // treated as "nothing to show" and instantly ticked: the tap attempts to
    // push the webview route (throwing only because of the missing test
    // platform binding) rather than calling field.didChange(true) first.
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(wrap(DynamicRegistrationForm(
      questions: const [
        RegQuestion(
            key: 'customDoc',
            type: 'linkAcknowledge',
            label: 'Custom Document',
            isRequired: true,
            hint: 'https://example.com/doc.pdf'),
      ],
      initialValues: const {},
      submitLabel: 'Register',
      onSubmit: (a) async => submitted = a,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Tap to open and read'), findsOneWidget);

    await tester.tap(find.text('Custom Document'));
    final errors = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    await tester.pump();
    FlutterError.onError = previousHandler;

    expect(
        errors.any((e) =>
            e.exception.toString().contains('WebViewPlatform') ||
            e.exception.toString().contains('platform implementation')),
        isTrue,
        reason: 'expected the tap to attempt building the WebView route');
    expect(find.text('Read — thank you!'), findsNothing,
        reason: 'a present hint URL must not tick before navigation happens');
    expect(submitted, isNull);
  });
}
