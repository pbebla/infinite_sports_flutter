// "My registration" way back (owner-approved 2026-11-14): a registered
// player can always reach their own registration — see it and, if they
// still owe, pay — even after sign-ups close.
//
// Where the fan's own registrations come from (checked against the code and
// BOTH rules files; no rules or Cloud Function change):
//   • `RegistrationsPublic` — the trigger-maintained mirror of every
//     registration's Config (functions/src/lib/public_mirrors.ts
//     registrationConfigProjection: the Config VERBATIM whatever its
//     Status; only a deleted/malformed Config removes the entry). So closed
//     registrations stay listed, with their Status and label. Rules:
//     `RegistrationsPublic/.read: true` in database.rules.stage1.json and
//     database.rules.json.
//   • `Registrations/<regId>/Submissions/<uid>` for each — rules:
//     `.read: auth != null && auth.uid == $uid` in both files (the fan's own
//     submission only; never the whole Submissions node).
//
// [watchMyRegistrations] combines the two LIVE (onValue): one answer only
// once the mirror AND every own-submission stream have answered (one
// loading state, no pop-in), then on every change. A failed read is
// forwarded as an error (a failed read is not "no registrations").

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';

/// One registration the signed-in fan has a submission in.
class MyRegistration {
  const MyRegistration({
    required this.regId,
    required this.config,
    required this.submission,
  });

  final String regId;
  final RegistrationConfig config;
  final RegSubmission submission;

  bool get paid => submission.paid;

  /// What the fan still owes: the SAME [discountedAmountOwed] (through
  /// discountedTotal) the status page shows — never a second formula. A
  /// team-code waiver makes a joiner's submission born Paid, so no team read
  /// is needed here.
  double get owed =>
      paid ? 0 : discountedAmountOwed(config: config, submission: submission);
}

/// The fan's registrations and the ones still open for sign-up.
class MyRegistrations {
  const MyRegistrations({required this.mine, required this.openForSignUp});

  /// Every existing registration (open or closed) the fan has a submission
  /// in, in the mirror's order.
  final List<MyRegistration> mine;

  /// Open registrations the fan has NOT registered for.
  final Map<String, RegistrationConfig> openForSignUp;

  /// The first registration the fan still owes money on (null = none).
  MyRegistration? get firstOwing {
    for (final m in mine) {
      if (m.owed > 0) return m;
    }
    return null;
  }

  static const empty = MyRegistrations(mine: [], openForSignUp: {});
}

/// "$54.00" — the payment screen's breakdown format.
String formatOwed(num amount) => '\$${amount.toStringAsFixed(2)}';

/// "Individual" / "Team captain" / "Team member" (the status page's labels).
String registrationPathLabel(String path) {
  switch (path) {
    case 'captain':
      return 'Team captain';
    case 'joiner':
      return 'Team member';
    default:
      return 'Individual';
  }
}

/// Every registration config in the mirror, whatever its Status (null-safe
/// parse; malformed children skipped).
Map<String, RegistrationConfig> allRegistrationsFromNode(Object? raw) {
  final out = <String, RegistrationConfig>{};
  void add(String regId, Object? node) {
    final config = RegistrationConfig.fromFirebase(node);
    if (config != null) out[regId] = config;
  }

  if (raw is Map) {
    raw.forEach((regId, node) => add(regId.toString(), node));
  } else if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      add('$i', raw[i]);
    }
  }
  return out;
}

String? _signedInUid() {
  try {
    return FirebaseAuth.instance.currentUser?.uid;
  } catch (_) {
    return null;
  }
}

/// The fan's own registrations, LIVE. [uidOf] defaults to the signed-in fan
/// (signed out: nothing is "mine" and no submission is read). [uidOf],
/// [configs] and [submissionFor] are test seams.
Stream<MyRegistrations> watchMyRegistrations({
  String? Function()? uidOf,
  Stream<Map<String, RegistrationConfig>> Function()? configs,
  Stream<RegSubmission?> Function(String regId)? submissionFor,
}) {
  final me = (uidOf ?? _signedInUid)();
  final configSource = configs ?? RegistrationService.watchAllRegistrations;
  final subSource = submissionFor ?? RegistrationService.watchMySubmission;

  late final StreamController<MyRegistrations> out;
  StreamSubscription<Map<String, RegistrationConfig>>? configSub;
  final subSubs = <String, StreamSubscription<RegSubmission?>>{};
  final answered = <String>{};
  final latestSub = <String, RegSubmission?>{};
  Map<String, RegistrationConfig>? latestConfigs;

  void emit() {
    final all = latestConfigs;
    if (all == null || out.isClosed) return;
    if (me != null && !all.keys.every(answered.contains)) return;
    final mine = <MyRegistration>[];
    final open = <String, RegistrationConfig>{};
    all.forEach((regId, config) {
      final submission = me == null ? null : latestSub[regId];
      if (submission != null) {
        mine.add(MyRegistration(
            regId: regId, config: config, submission: submission));
      } else if (config.isOpen) {
        open[regId] = config;
      }
    });
    out.add(MyRegistrations(mine: mine, openForSignUp: open));
  }

  void fail(Object e, StackTrace st) {
    if (!out.isClosed) out.addError(e, st);
  }

  void onConfigs(Map<String, RegistrationConfig> all) {
    latestConfigs = all;
    if (me != null) {
      // Removed registrations: stop following their submission.
      for (final regId in subSubs.keys.toList()) {
        if (!all.containsKey(regId)) {
          subSubs.remove(regId)?.cancel();
          answered.remove(regId);
          latestSub.remove(regId);
        }
      }
      for (final regId in all.keys) {
        if (subSubs.containsKey(regId)) continue;
        subSubs[regId] = subSource(regId).listen((s) {
          latestSub[regId] = s;
          answered.add(regId);
          emit();
        }, onError: fail);
      }
    }
    emit();
  }

  out = StreamController<MyRegistrations>(
    onListen: () {
      try {
        configSub = configSource().listen(onConfigs, onError: fail);
      } catch (e, st) {
        fail(e, st);
      }
    },
    onCancel: () async {
      await configSub?.cancel();
      for (final s in subSubs.values) {
        await s.cancel();
      }
      subSubs.clear();
    },
  );
  return out.stream;
}
