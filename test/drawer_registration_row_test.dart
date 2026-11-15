// "My registration" way back: the drawer's registration row. It shows its
// saved state at once (today's row until the fan's own registrations have
// answered) and then: enabled with "My registrations" when the fan has a
// registration of their own (open or closed), else today's label/state.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/registration/my_registrations.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

const _closed = RegistrationConfig(
  targetType: 'league',
  sport: 'Futsal',
  season: '16',
  status: 'closed',
  fee: 60,
  paymentMode: 'perPlayer',
);

MyRegistrations _mine({bool paid = false}) => MyRegistrations(mine: [
      MyRegistration(
          regId: 'futsal',
          config: _closed,
          submission:
              RegSubmission(path: 'individual', answers: const {}, paid: paid)),
    ], openForSignUp: const {});

void main() {
  test('before the own registrations answer: today\'s row (no waiting)', () {
    final r = drawerRegistrationRow(
        signedIn: true,
        signUpsOpen: false,
        signUpDetail: 'Sign Ups Closed',
        hasOpenRegistrations: false,
        mine: null);
    expect(r.title, 'Sign Up List');
    expect(r.subtitle, 'Sign Ups Closed');
    expect(r.enabled, isFalse);
    expect(r.opensRegistrationList, isFalse);
  });

  test(
      'a closed registration of mine that I owe on: My registrations, '
      'enabled, with the amount', () {
    final r = drawerRegistrationRow(
        signedIn: true,
        signUpsOpen: false,
        signUpDetail: 'Sign Ups Closed',
        hasOpenRegistrations: false,
        mine: _mine(),
        seasonPointer: (_) => '16');
    expect(r.title, 'My registrations');
    expect(r.enabled, isTrue);
    expect(r.opensRegistrationList, isTrue);
    expect(r.subtitle, 'You owe ${formatOwed(60)}');
  });

  test('paid in the only open one: All paid up (final round N1)', () {
    final r = drawerRegistrationRow(
        signedIn: true,
        signUpsOpen: true,
        signUpDetail: 'Sign Up for Futsal Season 16',
        hasOpenRegistrations: true,
        mine: _mine(paid: true),
        seasonPointer: (_) => '16');
    expect(r.title, 'My registrations');
    expect(r.subtitle, 'All paid up',
        reason: 'never "Sign Up for" a registration they already joined');
    expect(r.enabled, isTrue);
  });

  test('none of my own, an open registration: today\'s row', () {
    final r = drawerRegistrationRow(
        signedIn: true,
        signUpsOpen: true,
        signUpDetail: 'Sign Up for Futsal 17',
        hasOpenRegistrations: true,
        mine: MyRegistrations.empty);
    expect(r.title, 'Sign Up List');
    expect(r.enabled, isTrue);
    expect(r.opensRegistrationList, isTrue);
  });

  test('signed out: never enabled', () {
    final r = drawerRegistrationRow(
        signedIn: false,
        signUpsOpen: true,
        signUpDetail: 'Sign Ups Open',
        hasOpenRegistrations: true,
        mine: null);
    expect(r.enabled, isFalse);
  });

  test('fix round Important 4: an old owing registration: no "You owe"', () {
    final r = drawerRegistrationRow(
        signedIn: true,
        signUpsOpen: false,
        signUpDetail: 'Sign Ups Closed',
        hasOpenRegistrations: false,
        mine: _mine(),
        seasonPointer: (_) => '17');
    expect(r.title, 'My registrations', reason: 'still reachable');
    expect(r.subtitle, 'View your registrations');
  });

  // Way back fix round, Minor 4: when the drawer row becomes "My
  // registrations", the OLD sign-up page (legacy Sign Up Status, no
  // new-style registration open) must stay reachable from the list.
  group('the old sign-up page stays reachable', () {
    test('legacy sign-ups open, no new-style one: the list offers it', () {
      final r = drawerRegistrationRow(
          signedIn: true,
          signUpsOpen: true,
          signUpDetail: 'Sign Up for Futsal Season 17',
          hasOpenRegistrations: false,
          mine: _mine(paid: true),
          seasonPointer: (_) => '16');
      expect(r.title, 'My registrations');
      expect(r.offersLegacySignUp, isTrue);
    });

    test('a new-style registration is open: no legacy offer', () {
      final r = drawerRegistrationRow(
          signedIn: true,
          signUpsOpen: true,
          signUpDetail: 'Sign Ups Open',
          hasOpenRegistrations: true,
          mine: _mine(paid: true),
          seasonPointer: (_) => '16');
      expect(r.offersLegacySignUp, isFalse);
    });

    test('sign-ups closed: no legacy offer', () {
      final r = drawerRegistrationRow(
          signedIn: true,
          signUpsOpen: false,
          signUpDetail: 'Sign Ups Closed',
          hasOpenRegistrations: false,
          mine: _mine(paid: true),
          seasonPointer: (_) => '16');
      expect(r.offersLegacySignUp, isFalse);
    });

    test('no registration of my own: today\'s row goes there directly', () {
      final r = drawerRegistrationRow(
          signedIn: true,
          signUpsOpen: true,
          signUpDetail: 'Sign Up for Futsal Season 17',
          hasOpenRegistrations: false,
          mine: MyRegistrations.empty);
      expect(r.title, 'Sign Up List');
      expect(r.opensRegistrationList, isFalse);
      expect(r.offersLegacySignUp, isFalse);
    });
  });

  // Final small round, N1: the subtitle under "My registrations" never
  // invites the fan to sign up for a registration they already joined.
  group('My registrations subtitle', () {
    const basket = RegistrationConfig(
      targetType: 'league',
      sport: 'Basketball',
      season: '9',
      status: 'open',
      fee: 40,
      paymentMode: 'perPlayer',
    );
    const flag = RegistrationConfig(
      targetType: 'league',
      sport: 'Flag Football',
      season: '4',
      status: 'open',
      fee: 40,
      paymentMode: 'perPlayer',
    );

    MyRegistrations withOpen(Map<String, RegistrationConfig> open,
            {bool paid = true}) =>
        MyRegistrations(mine: _mine(paid: paid).mine, openForSignUp: open);

    test('joined one of two open: Sign Up for the other', () {
      final r = drawerRegistrationRow(
          signedIn: true,
          signUpsOpen: true,
          signUpDetail: 'Sign Ups Open',
          hasOpenRegistrations: true,
          mine: withOpen({'basket': basket}),
          seasonPointer: (_) => '16');
      expect(r.subtitle, 'Sign Up for ${basket.label}');
    });

    test('several open not joined: Sign Ups Open', () {
      final r = drawerRegistrationRow(
          signedIn: true,
          signUpsOpen: true,
          signUpDetail: 'Sign Up for Futsal Season 16',
          hasOpenRegistrations: true,
          mine: withOpen({'basket': basket, 'flag': flag}),
          seasonPointer: (_) => '16');
      expect(r.subtitle, 'Sign Ups Open');
    });

    test('owing on a current registration wins: You owe (unchanged)', () {
      final r = drawerRegistrationRow(
          signedIn: true,
          signUpsOpen: true,
          signUpDetail: 'Sign Ups Open',
          hasOpenRegistrations: true,
          mine: withOpen({'basket': basket}, paid: false),
          seasonPointer: (_) => '16');
      expect(r.subtitle, 'You owe ${formatOwed(60)}');
    });

    test('old-style sign-up offered, nothing new to join: its detail', () {
      final r = drawerRegistrationRow(
          signedIn: true,
          signUpsOpen: true,
          signUpDetail: 'Sign Up for Futsal Season 17',
          hasOpenRegistrations: false,
          mine: _mine(paid: true),
          seasonPointer: (_) => '16');
      expect(r.subtitle, 'Sign Up for Futsal Season 17');
    });

    test('an old unpaid closed registration, none current: View', () {
      final r = drawerRegistrationRow(
          signedIn: true,
          signUpsOpen: false,
          signUpDetail: 'Sign Ups Closed',
          hasOpenRegistrations: false,
          mine: _mine(),
          seasonPointer: (_) => '17');
      expect(r.subtitle, 'View your registrations');
    });
  });
}
