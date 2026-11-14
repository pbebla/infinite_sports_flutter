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
import 'package:infinite_sports_flutter/misc/bounded_read.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';

/// One registration the signed-in fan has a submission in.
class MyRegistration {
  const MyRegistration({
    required this.regId,
    required this.config,
    required this.submission,
    this.codeWaivesPayment = false,
  });

  final String regId;
  final RegistrationConfig config;
  final RegSubmission submission;

  /// The member's team has "code waives payment" on — read from the SAME
  /// team node the status page reads (fix round, Minor 2).
  final bool codeWaivesPayment;

  bool get paid => submission.paid;

  /// The status page's chip decision for this registration (fix round,
  /// Minor 1).
  ({RegistrationChipKind kind, String label, double owed, bool settled})
      get chip => registrationChipFor(
          config: config,
          submission: submission,
          codeWaivesPayment: codeWaivesPayment);

  /// What the fan still owes: the SAME [discountedAmountOwed] (through
  /// discountedTotal), with the same team-code waiver, the status page
  /// shows — never a second formula.
  double get owed => paid
      ? 0
      : discountedAmountOwed(
          config: config,
          submission: submission,
          codeWaivesPayment: codeWaivesPayment);
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

/// Whether a registration is CURRENT — the only kind the home banner and
/// the drawer's "You owe" nag about (way back fix round, Important 4,
/// owner's ruling; the registration list shows every registration):
///   • open → current;
///   • closed, league → current only while its Season >= the live public
///     season pointer for its Sport (`>=`: a registration for an upcoming
///     season can close before that season is published);
///   • closed, tournament → current only while the tournament still exists
///     and is not finished ([activeTournamentIds]);
///   • pointer / tournaments not known (null) or unparsable → a closed
///     registration is NOT current (never nag on a guess).
bool isCurrentRegistration(
  RegistrationConfig config, {
  required String? Function(String sport) seasonPointer,
  required Set<String>? activeTournamentIds,
}) {
  if (config.isOpen) return true;
  if (config.targetType == 'tournament') {
    final active = activeTournamentIds;
    return active != null && active.contains(config.tournamentId);
  }
  final pointer = int.tryParse(seasonPointer(config.sport) ?? '');
  final season = int.tryParse(config.season);
  if (pointer == null || season == null) return false;
  return season >= pointer;
}

/// THE pick for the home banner and the drawer: the first registration the
/// fan still owes on that is current ([isCurrentRegistration]); null =
/// none (or [mine] not known yet).
MyRegistration? firstCurrentOwing(
  MyRegistrations? mine, {
  required String? Function(String sport) seasonPointer,
  required Set<String>? activeTournamentIds,
}) {
  if (mine == null) return null;
  for (final m in mine.mine) {
    if (m.owed > 0 &&
        isCurrentRegistration(m.config,
            seasonPointer: seasonPointer,
            activeTournamentIds: activeTournamentIds)) {
      return m;
    }
  }
  return null;
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
  Stream<RegTeam?> Function(String regId, String teamId)? teamFor,
  Duration firstAnswerBound = kRevealReadTimeout,
}) {
  final me = (uidOf ?? _signedInUid)();
  final configSource = configs ?? RegistrationService.watchAllRegistrations;
  final subSource = submissionFor ?? RegistrationService.watchMySubmission;
  final teamSource = teamFor ?? RegistrationService.watchTeam;

  // Fix round, Minor 2: an unpaid team member's waiver comes from their
  // team node, exactly as on the status page (RegistrationService.watchTeam;
  // a denied read — the target rules let only the captain read
  // Teams/<tid> — is null there and here). Answers gate the emission like
  // the submissions do.
  final teamIds = <String, String>{};
  final teamSubs = <String, StreamSubscription<RegTeam?>>{};
  final teamAnswered = <String>{};
  final waives = <String, bool>{};

  void dropTeam(String regId) {
    teamSubs.remove(regId)?.cancel();
    teamIds.remove(regId);
    teamAnswered.remove(regId);
    waives.remove(regId);
  }

  void followTeam(String regId, RegSubmission? s, void Function() emit) {
    final teamId = (s != null && s.path == 'joiner' && !s.paid) ? s.teamId : '';
    if (teamSubs.containsKey(regId) && teamIds[regId] == teamId) return;
    dropTeam(regId);
    if (teamId.isEmpty) return;
    teamIds[regId] = teamId;
    teamSubs[regId] = teamSource(regId, teamId).listen((team) {
      waives[regId] = team?.codeWaivesPayment ?? false;
      teamAnswered.add(regId);
      emit();
    }, onError: (Object _) {
      // Same as the status page's degraded read: not waived.
      waives[regId] = false;
      teamAnswered.add(regId);
      emit();
    });
  }

  late final StreamController<MyRegistrations> out;
  StreamSubscription<Map<String, RegistrationConfig>>? configSub;
  final subSubs = <String, StreamSubscription<RegSubmission?>>{};
  final answered = <String>{};
  final latestSub = <String, RegSubmission?>{};
  Map<String, RegistrationConfig>? latestConfigs;

  // Way back fix round, Important 2: no first answer within the bound (the
  // same 8 s checkEntry uses) is an error — the list shows "couldn't load"
  // with Retry instead of a skeleton forever — but listening goes on, and
  // a late answer then arrives as data.
  Timer? firstAnswerTimer;
  var answeredOnce = false;

  void emit() {
    final all = latestConfigs;
    if (all == null || out.isClosed) return;
    if (me != null && !all.keys.every(answered.contains)) return;
    if (me != null && !teamSubs.keys.every(teamAnswered.contains)) return;
    final mine = <MyRegistration>[];
    final open = <String, RegistrationConfig>{};
    all.forEach((regId, config) {
      final submission = me == null ? null : latestSub[regId];
      if (submission != null) {
        mine.add(MyRegistration(
            regId: regId,
            config: config,
            submission: submission,
            codeWaivesPayment: waives[regId] ?? false));
      } else if (config.isOpen) {
        open[regId] = config;
      }
    });
    answeredOnce = true;
    firstAnswerTimer?.cancel();
    firstAnswerTimer = null;
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
          dropTeam(regId);
        }
      }
      for (final regId in all.keys) {
        if (subSubs.containsKey(regId)) continue;
        subSubs[regId] = subSource(regId).listen((s) {
          latestSub[regId] = s;
          answered.add(regId);
          followTeam(regId, s, emit);
          emit();
        }, onError: fail);
      }
    }
    emit();
  }

  out = StreamController<MyRegistrations>(
    onListen: () {
      firstAnswerTimer = Timer(firstAnswerBound, () {
        firstAnswerTimer = null;
        if (!answeredOnce && !out.isClosed) {
          out.addError(TimeoutException(
              'My registrations: no answer', firstAnswerBound));
        }
      });
      try {
        configSub = configSource().listen(onConfigs, onError: fail);
      } catch (e, st) {
        fail(e, st);
      }
    },
    onCancel: () async {
      firstAnswerTimer?.cancel();
      await configSub?.cancel();
      for (final s in subSubs.values) {
        await s.cancel();
      }
      subSubs.clear();
      for (final t in teamSubs.values) {
        await t.cancel();
      }
      teamSubs.clear();
    },
  );
  return out.stream;
}
