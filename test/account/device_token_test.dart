// The phone's FCM token under Users/<uid>/Token: removed on sign-out and on
// "All notifications" OFF only when it is THIS phone's token, never blocking
// (offline, slow, deleted account), and never written while the master
// switch is off. Firebase-free: the node and the device token are seams.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/account/session_sign_out.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeTokenNode implements UserTokenNode {
  FakeTokenNode([Map<String, Object?>? initial]) : values = {...?initial};
  final Map<String, Object?> values;
  final List<String> calls = [];
  Object? readError;
  Completer<Object?>? hangRead;

  @override
  Future<Object?> read(String uid) async {
    calls.add('read:$uid');
    if (hangRead != null) return hangRead!.future;
    if (readError != null) throw readError!;
    return values[uid];
  }

  @override
  Future<void> write(String uid, String token) async {
    calls.add('write:$uid');
    values[uid] = token;
  }

  @override
  Future<void> remove(String uid) async {
    calls.add('remove:$uid');
    values.remove(uid);
  }
}

void main() {
  group('removeUserTokenIfThisDevice', () {
    test('removes the node when it holds this phone\'s token', () async {
      final node = FakeTokenNode({'uid_alice': 'tok_phone'});
      final removed = await removeUserTokenIfThisDevice('uid_alice',
          node: node, deviceToken: () async => 'tok_phone');
      expect(removed, isTrue);
      expect(node.values.containsKey('uid_alice'), isFalse);
    });

    test('leaves another phone\'s token alone', () async {
      final node = FakeTokenNode({'uid_alice': 'tok_other_phone'});
      final removed = await removeUserTokenIfThisDevice('uid_alice',
          node: node, deviceToken: () async => 'tok_phone');
      expect(removed, isFalse);
      expect(node.values['uid_alice'], 'tok_other_phone');
      expect(node.calls, isNot(contains('remove:uid_alice')));
    });

    test('a just-deleted account (no node) is a silent no-op', () async {
      final node = FakeTokenNode();
      final removed = await removeUserTokenIfThisDevice('uid_alice',
          node: node, deviceToken: () async => 'tok_phone');
      expect(removed, isFalse);
      expect(node.calls, ['read:uid_alice']);
    });

    test('signed out (no uid) or no device token: nothing touched', () async {
      final node = FakeTokenNode({'uid_alice': 'tok_phone'});
      expect(
          await removeUserTokenIfThisDevice(null,
              node: node, deviceToken: () async => 'tok_phone'),
          isFalse);
      expect(
          await removeUserTokenIfThisDevice('uid_alice',
              node: node, deviceToken: () async => null),
          isFalse);
      expect(node.calls, isEmpty);
    });

    test('a failing read is swallowed', () async {
      final node = FakeTokenNode({'uid_alice': 'tok_phone'})
        ..readError = Exception('permission-denied');
      expect(
          await removeUserTokenIfThisDevice('uid_alice',
              node: node, deviceToken: () async => 'tok_phone'),
          isFalse);
    });

    test('a hanging read (offline) gives up after the timeout', () async {
      final node = FakeTokenNode()..hangRead = Completer<Object?>();
      final sw = Stopwatch()..start();
      final removed = await removeUserTokenIfThisDevice('uid_alice',
          node: node,
          deviceToken: () async => 'tok_phone',
          timeout: const Duration(milliseconds: 50));
      expect(removed, isFalse);
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  group('uploadTokenForUid (master switch gate)', () {
    test('master ON writes the token', () async {
      SharedPreferences.setMockInitialValues({});
      final node = FakeTokenNode();
      await uploadTokenForUid('uid_alice', 'tok_phone', node: node);
      expect(node.values['uid_alice'], 'tok_phone');
    });

    test('app start with master OFF writes no token', () async {
      SharedPreferences.setMockInitialValues(
          {'notificationsMasterEnabled': false});
      final node = FakeTokenNode();
      await uploadTokenForUid('uid_alice', 'tok_phone', node: node);
      expect(node.calls, isEmpty);
    });

    test('a failing write is swallowed', () async {
      SharedPreferences.setMockInitialValues({});
      await uploadTokenForUid('uid_alice', 'tok_phone',
          node: _ThrowingNode());
    });
  });

  group('signOutAndClearSession', () {
    test('detaches the token BEFORE signing out', () async {
      final calls = <String>[];
      await signOutAndClearSession(
        detachToken: () async => calls.add('detach'),
        firebaseSignOut: () async => calls.add('signOut'),
      );
      expect(calls, ['detach', 'signOut']);
    });

    test('a failing detach never blocks the sign-out', () async {
      final calls = <String>[];
      await signOutAndClearSession(
        detachToken: () async => throw Exception('offline'),
        firebaseSignOut: () async => calls.add('signOut'),
      );
      expect(calls, ['signOut']);
    });

    test('a hanging detach is cut off at about 2 seconds', () async {
      final calls = <String>[];
      final sw = Stopwatch()..start();
      await signOutAndClearSession(
        detachToken: () => Completer<void>().future,
        firebaseSignOut: () async => calls.add('signOut'),
      );
      expect(calls, ['signOut']);
      expect(sw.elapsed, lessThan(const Duration(seconds: 4)));
    });
  });
}

class _ThrowingNode extends FakeTokenNode {
  @override
  Future<void> write(String uid, String token) async =>
      throw Exception('offline');
}
