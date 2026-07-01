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

    // Empty-URL acknowledge (as in the default template before the admin
    // sets a URL): tapping the tile marks it read without opening a webview.
    await tester.tap(find.text('Waiver Conditions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(submitted, isNotNull);
    expect(submitted!['waiver'], true);
  });
}
