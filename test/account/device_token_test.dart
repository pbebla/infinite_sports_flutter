// The phone's FCM token under Users/<uid>/Token: removed on sign-out and on
// "All notifications" OFF only when it is THIS phone's token, never blocking
// (offline, slow, deleted account), and never written while the master
// switch is off. Firebase-free: the node and the device token are seams.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/account/session_sign_out.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simulates the Realtime Database: a [server] value and this phone's
/// [local] cache (persistence on). `removeIf` follows the transaction
/// protocol: the handler first runs on the LOCAL value; an abort ends it;
/// a success is only committed if the local value matches the server's,
/// otherwise the handler re-runs with the server value.
class FakeTokenNode implements UserTokenNode {
  FakeTokenNode([Map<String, Object?>? initial])
      : server = {...?initial},
        local = {...?initial};
  final Map<String, Object?> server;
  final Map<String, Object?> local;
  final List<String> calls = [];
  Object? removeError;
  Completer<bool>? hangRemove;
  Completer<void>? hangWrite;

  /// Legacy name used by the older tests: the server value.
  Map<String, Object?> get values => server;

  @override
  Future<void> write(String uid, String token) async {
    calls.add('write:$uid');
    if (hangWrite != null) return hangWrite!.future;
    server[uid] = token;
    local[uid] = token;
  }

  @override
  Future<bool> removeIf(
      String uid, bool Function(Object? current) shouldRemove) async {
    calls.add('removeIf:$uid');
    if (hangRemove != null) return hangRemove!.future;
    if (removeError != null) throw removeError!;
    final cached = local[uid];
    if (!shouldRemove(cached)) return false;
    final real = server[uid];
    if (real != cached && !shouldRemove(real)) {
      local[uid] = real; // the server's answer refreshes the cache
      return false;
    }
    final existed = server.containsKey(uid);
    server.remove(uid);
    local.remove(uid);
    return existed;
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

    });

    test('a just-deleted account (no node) is a silent no-op', () async {
      final node = FakeTokenNode();
      final removed = await removeUserTokenIfThisDevice('uid_alice',
          node: node, deviceToken: () async => 'tok_phone');
      expect(removed, isFalse);
      expect(node.server, isEmpty);
    });

    test(
        "STALE cache holds this phone's token but the server holds another "
        "phone's: the other phone's token survives", () async {
      final node = FakeTokenNode()
        ..local['uid_alice'] = 'tok_phone'
        ..server['uid_alice'] = 'tok_other_phone';
      final removed = await removeUserTokenIfThisDevice('uid_alice',
          node: node, deviceToken: () async => 'tok_phone');
      expect(removed, isFalse);
      expect(node.server['uid_alice'], 'tok_other_phone');
    });

    test("empty cache but the server holds this phone's token: removed",
        () async {
      final node = FakeTokenNode()..server['uid_alice'] = 'tok_phone';
      final removed = await removeUserTokenIfThisDevice('uid_alice',
          node: node, deviceToken: () async => 'tok_phone');
      expect(removed, isTrue);
      expect(node.server.containsKey('uid_alice'), isFalse);
    });

    test("empty cache and the server holds another phone's token: kept",
        () async {
      final node = FakeTokenNode()..server['uid_alice'] = 'tok_other_phone';
      await removeUserTokenIfThisDevice('uid_alice',
          node: node, deviceToken: () async => 'tok_phone');
      expect(node.server['uid_alice'], 'tok_other_phone');
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

    test('a failing transaction is swallowed', () async {
      final node = FakeTokenNode({'uid_alice': 'tok_phone'})
        ..removeError = Exception('permission-denied');
      expect(
          await removeUserTokenIfThisDevice('uid_alice',
              node: node, deviceToken: () async => 'tok_phone'),
          isFalse);
    });

    test('a hanging transaction (offline) gives up after the timeout',
        () async {
      final node = FakeTokenNode()..hangRemove = Completer<bool>();
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

    test('a never-confirmed write (offline) stops waiting at the bound',
        () async {
      SharedPreferences.setMockInitialValues({});
      final node = FakeTokenNode()..hangWrite = Completer<void>();
      final sw = Stopwatch()..start();
      await uploadTokenForUid('uid_alice', 'tok_phone',
          node: node, timeout: const Duration(milliseconds: 50));
      expect(node.calls, ['write:uid_alice']);
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
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
