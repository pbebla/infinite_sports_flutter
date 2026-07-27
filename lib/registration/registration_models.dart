// Pure registration-engine models + helpers (Leagues epic L1, phases L1a-L1b).
//
// NO Flutter/Firebase imports — unit-tested directly. This file is
// intentionally DUPLICATED byte-for-byte in both repos (the apps share no
// code; precedent: trophy/tournament models). Keep the copies identical:
//   Manager: lib/models/registration_models.dart
//   Fan:     lib/registration/registration_models.dart

import 'dart:math';

// ---------------------------------------------------------------------------
// Question model
// ---------------------------------------------------------------------------

/// Every question type the dynamic form engine understands.
const List<String> kRegQuestionTypes = [
  'shortText',
  'paragraph',
  'number',
  'phone',
  'email',
  'date',
  'dropdown',
  'singleChoice',
  'multiChoice',
  'yesNo',
  'height',
  'linkAcknowledge',
];

/// Types that carry an options list.
const List<String> kRegChoiceTypes = ['dropdown', 'singleChoice', 'multiChoice'];

/// Who sees a question: every path, or one specific registration path.
const List<String> kRegVisibilities = ['all', 'individual', 'captain', 'joiner'];

class RegQuestion {
  final String key; // stable id; well-known keys map to profile fields
  final String type; // one of kRegQuestionTypes
  final String label;
  final bool isRequired; // serialized under the map key 'required'
  final String visibility; // one of kRegVisibilities
  final List<String> options; // choice types only
  final String hint; // for linkAcknowledge this holds the URL to open

  const RegQuestion({
    required this.key,
    required this.type,
    required this.label,
    this.isRequired = false,
    this.visibility = 'all',
    this.options = const [],
    this.hint = '',
  });

  /// True when a registrant on [path] ('individual'|'captain'|'joiner')
  /// should see this question.
  bool visibleFor(String path) => visibility == 'all' || visibility == path;

  Map<String, dynamic> toMap() => {
        'key': key,
        'type': type,
        'label': label,
        'required': isRequired,
        'visibility': visibility,
        if (options.isNotEmpty) 'options': options,
        if (hint.isNotEmpty) 'hint': hint,
      };

  /// Defensive parse; returns null for malformed nodes.
  static RegQuestion? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key']?.toString() ?? '';
    final type = raw['type']?.toString() ?? '';
    if (key.isEmpty || !kRegQuestionTypes.contains(type)) return null;
    final rawOptions = raw['options'];
    final rawVisibility = raw['visibility']?.toString() ?? 'all';
    return RegQuestion(
      key: key,
      type: type,
      label: raw['label']?.toString() ?? key,
      isRequired: raw['required'] == true,
      visibility:
          kRegVisibilities.contains(rawVisibility) ? rawVisibility : 'all',
      options: rawOptions is List
          ? rawOptions.map((o) => o.toString()).toList()
          : const <String>[],
      hint: raw['hint']?.toString() ?? '',
    );
  }

  RegQuestion copyWith({
    String? key,
    String? type,
    String? label,
    bool? isRequired,
    String? visibility,
    List<String>? options,
    String? hint,
  }) =>
      RegQuestion(
        key: key ?? this.key,
        type: type ?? this.type,
        label: label ?? this.label,
        isRequired: isRequired ?? this.isRequired,
        visibility: visibility ?? this.visibility,
        options: options ?? this.options,
        hint: hint ?? this.hint,
      );
}

/// Parses a Form/FormTemplates node into an ordered question list. RTDB may
/// return a List OR a Map keyed by index strings; both are handled. Malformed
/// entries are skipped.
List<RegQuestion> regQuestionsFromNode(Object? raw) {
  final out = <RegQuestion>[];
  if (raw is List) {
    for (final item in raw) {
      final q = RegQuestion.fromMap(item);
      if (q != null) out.add(q);
    }
  } else if (raw is Map) {
    final entries = raw.entries.toList()
      ..sort((a, b) => (int.tryParse(a.key.toString()) ?? 0)
          .compareTo(int.tryParse(b.key.toString()) ?? 0));
    for (final e in entries) {
      final q = RegQuestion.fromMap(e.value);
      if (q != null) out.add(q);
    }
  }
  return out;
}

/// Serializes an ordered question list for a Form/FormTemplates node.
List<Map<String, dynamic>> regQuestionsToList(List<RegQuestion> questions) =>
    questions.map((q) => q.toMap()).toList();

// ---------------------------------------------------------------------------
// Input hygiene (engine-wide)
// ---------------------------------------------------------------------------

/// Uppercases the first letter of each whitespace-separated word, leaving the
/// rest of the word unchanged ("john doe" -> "John Doe").
String capitalizeWords(String input) {
  return input
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Trims and collapses every whitespace run to a single space
/// ("  a   b  " -> "a b").
String collapseTrailingSpaces(String input) =>
    input.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Keeps digits only ("(408) 693-9436" -> "4086939436"). Stored form.
String normalizePhone(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

/// Displays a stored phone as (408) 693-9436. 11-digit numbers with a leading
/// 1 lose the country code; anything else is returned unchanged.
String formatPhone(String input) {
  var d = normalizePhone(input);
  if (d.length == 11 && d.startsWith('1')) d = d.substring(1);
  if (d.length != 10) return input;
  return '(${d.substring(0, 3)}) ${d.substring(3, 6)}-${d.substring(6)}';
}

/// Suggests a stable camelCase key from a label ("First Name" -> "firstName").
String suggestKeyFromLabel(String label) {
  final words = label
      .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  final first = words.first.toLowerCase();
  final rest = words
      .skip(1)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase());
  return [first, ...rest].join();
}

/// Applies type-aware hygiene to raw form values before they are written:
/// shortText -> capitalize words + collapse spaces; paragraph -> collapse
/// spaces; phone -> digits only; number -> num when parseable; date
/// (DateTime) -> "MM/DD/YYYY" string. Null values are dropped. Keys without
/// a matching question pass through unchanged.
Map<String, dynamic> cleanAnswers(
    List<RegQuestion> questions, Map<String, dynamic> raw) {
  final byKey = {for (final q in questions) q.key: q};
  final out = <String, dynamic>{};
  raw.forEach((key, value) {
    if (value == null) return;
    final q = byKey[key];
    switch (q?.type) {
      case 'shortText':
        out[key] = capitalizeWords(collapseTrailingSpaces(value.toString()));
      case 'paragraph':
        out[key] = collapseTrailingSpaces(value.toString());
      case 'phone':
        out[key] = normalizePhone(value.toString());
      case 'number':
        out[key] = num.tryParse(value.toString()) ?? value.toString();
      case 'date':
        out[key] = value is DateTime
            ? '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}'
            : value.toString();
      default:
        out[key] = value;
    }
  });
  return out;
}

// ---------------------------------------------------------------------------
// Registration config
// ---------------------------------------------------------------------------

/// Valid RegistrationConfig.paymentMode values. 'both' charges the per-player
/// fee to individuals and the flat teamFee to captains.
const List<String> kRegPaymentModes = ['perPlayer', 'teamFee', 'both'];

class RegistrationConfig {
  final String targetType; // 'league' | 'tournament'
  final String sport; // league sport key / tournament sport label
  final String season; // league season number as string; '' for tournament
  final String tournamentId; // '' for league targets
  final String tournamentName; // legacy dual-write bucket for tournaments
  final String status; // 'open' | 'closed'
  final num fee; // per-player fee
  final num teamFee; // flat fee owed by a team's captain
  final String feeNote;
  final String paymentMode; // 'perPlayer' | 'teamFee' | 'both'
  final bool venmo;
  final bool zelle;
  final bool stripe;
  final int createdAt; // millisecondsSinceEpoch

  const RegistrationConfig({
    required this.targetType,
    required this.sport,
    this.season = '',
    this.tournamentId = '',
    this.tournamentName = '',
    this.status = 'closed',
    this.fee = 0,
    this.teamFee = 0,
    this.feeNote = '',
    this.paymentMode = 'perPlayer',
    this.venmo = true,
    this.zelle = true,
    this.stripe = false,
    this.createdAt = 0,
  });

  bool get isOpen => status == 'open';

  /// Human label, e.g. "Futsal Season 17" or the tournament's name.
  String get label => targetType == 'tournament'
      ? (tournamentName.isNotEmpty ? tournamentName : tournamentId)
      : '$sport Season $season';

  Map<String, dynamic> toFirebaseMap() => {
        'TargetType': targetType,
        'Sport': sport,
        if (season.isNotEmpty) 'Season': season,
        if (tournamentId.isNotEmpty) 'TournamentId': tournamentId,
        if (tournamentName.isNotEmpty) 'TournamentName': tournamentName,
        'Status': status,
        'Fee': fee,
        'TeamFee': teamFee,
        'FeeNote': feeNote,
        'PaymentMode': paymentMode,
        'Methods': {'venmo': venmo, 'zelle': zelle, 'stripe': stripe},
        'CreatedAt': createdAt,
      };

  /// Defensive parse; returns null for malformed nodes.
  static RegistrationConfig? fromFirebase(Object? raw) {
    if (raw is! Map) return null;
    final targetType = raw['TargetType']?.toString() ?? '';
    if (targetType != 'league' && targetType != 'tournament') return null;
    final methods = raw['Methods'];
    bool method(String key, bool fallback) =>
        methods is Map ? methods[key] == true : fallback;
    return RegistrationConfig(
      targetType: targetType,
      sport: raw['Sport']?.toString() ?? '',
      season: raw['Season']?.toString() ?? '',
      tournamentId: raw['TournamentId']?.toString() ?? '',
      tournamentName: raw['TournamentName']?.toString() ?? '',
      status: raw['Status']?.toString() == 'open' ? 'open' : 'closed',
      fee: raw['Fee'] is num
          ? raw['Fee'] as num
          : num.tryParse(raw['Fee']?.toString() ?? '') ?? 0,
      teamFee: raw['TeamFee'] is num
          ? raw['TeamFee'] as num
          : num.tryParse(raw['TeamFee']?.toString() ?? '') ?? 0,
      feeNote: raw['FeeNote']?.toString() ?? '',
      paymentMode: kRegPaymentModes.contains(raw['PaymentMode']?.toString())
          ? raw['PaymentMode'].toString()
          : 'perPlayer',
      venmo: method('venmo', true),
      zelle: method('zelle', true),
      stripe: method('stripe', false),
      createdAt: int.tryParse(raw['CreatedAt']?.toString() ?? '') ?? 0,
    );
  }
}

/// regId for a league-season registration: "Futsal-17".
String leagueRegId(String sport, String season) => '$sport-$season';

/// regId for a tournament registration: "T-{tournamentId}".
String tournamentRegId(String tournamentId) => 'T-$tournamentId';

/// The regId a config lives under.
String regIdFor(RegistrationConfig c) => c.targetType == 'tournament'
    ? tournamentRegId(c.tournamentId)
    : leagueRegId(c.sport, c.season);

/// Where the legacy dual-write goes. Leagues keep the existing
/// Sign Ups/{Sport}/{Season}/... buckets; tournament targets write the
/// equivalent Sign Ups/{TournamentName}/{tournamentId}/... buckets (name
/// falls back to the id when unset).
({String league, String season}) legacySignUpTarget(RegistrationConfig c) =>
    c.targetType == 'tournament'
        ? (
            league:
                c.tournamentName.isNotEmpty ? c.tournamentName : c.tournamentId,
            season: c.tournamentId,
          )
        : (league: c.sport, season: c.season);

// ---------------------------------------------------------------------------
// Named form templates (FormTemplates/{id})
// ---------------------------------------------------------------------------

/// A saved, named question list under FormTemplates/{id}. Legacy data (from
/// before named templates existed) stores a plain question List directly at
/// FormTemplates/{id} — [fromNode] treats that shape as a template named
/// 'Default'. New data stores {'Name': ..., 'Questions': [...]}.
class RegTemplate {
  final String id;
  final String name;
  final List<RegQuestion> questions;

  const RegTemplate({
    required this.id,
    required this.name,
    required this.questions,
  });

  /// Parses a FormTemplates/{id} node. Accepts the legacy flat-List shape
  /// (name defaults to 'Default') and the new {'Name','Questions'} shape.
  /// Never returns null — malformed/missing nodes become an empty template.
  static RegTemplate fromNode(String id, Object? node) {
    // New shape: a Map carrying a 'Questions' key. (A legacy index-keyed
    // question Map from RTDB has no 'Questions' key, so this test is safe.)
    if (node is Map && node.containsKey('Questions')) {
      return RegTemplate(
        id: id,
        name: node['Name']?.toString() ?? id,
        questions: regQuestionsFromNode(node['Questions']),
      );
    }
    // Legacy shape: node is the question list/map itself (List, or an
    // index-keyed Map from RTDB).
    return RegTemplate(
      id: id,
      name: 'Default',
      questions: regQuestionsFromNode(node),
    );
  }

  Map<String, dynamic> toMap() => {
        'Name': name,
        'Questions': regQuestionsToList(questions),
      };

  RegTemplate copyWith({String? name, List<RegQuestion>? questions}) =>
      RegTemplate(
        id: id,
        name: name ?? this.name,
        questions: questions ?? this.questions,
      );
}

// ---------------------------------------------------------------------------
// Submission
// ---------------------------------------------------------------------------

class RegSubmission {
  final String path; // 'individual' | 'joiner' | 'captain'
  final Map<String, dynamic> answers;
  final String teamId; // '' until team paths land (L1b)
  final bool paid;
  final String paidVia; // '' | 'team code' | 'card' | 'manual'
  final num? paidAmount; // dollars actually charged/recorded; null if unknown
  final String displayName; // account display name at submit time
  final int submittedAt; // millisecondsSinceEpoch

  // -- Manual payment adjustment (Infinite Insiders P1, Task M1/F1) ----
  // Written by the Manager's RegistrationService.adjustSubmissionAmount/
  // clearAdjustment; read here so the fan payment/status screens can show
  // the same adjusted amount live (Task F1). Keep this block in sync with
  // lib/models/registration_models.dart in the Manager repo.
  final double? adjustedFee; // absolute new total owed (wins over discountPct)
  final double? discountPct; // percent off the base fee
  final String discountSource; // '' | 'manual' | 'first_timer_promo' | 'insider_tier'
  final String adjustReason; // required reason for the most recent adjustment

  // -- Insider promo-code entry (Infinite Insiders P2, Task F3) --------
  // Stamped by RegistrationService.submitIndividual/submitCaptain when the
  // registrant entered a code that passed evaluateCode (lib/registration/
  // promo_engine.dart). InsiderCode/FirstTimer are written whenever the code
  // validated, REGARDLESS of whether a discount applied (referral counting
  // itself is payment-side, spec §10/Task X1 — not this task). DiscountPct/
  // DiscountSource/EligibleFee above are additionally set only when the
  // per-registration promo was active AND the registrant was a first-timer
  // (spec §4/§5) — DiscountSource becomes 'first_timer_promo' rather than
  // 'manual' in that case; see promo_engine.dart's bestDiscountedTotal for
  // how the fan payment screen reconciles the two possible sources.
  //
  // -- Insider tier discount at checkout (Infinite Insiders P3, Task F5) --
  // On the INDIVIDUAL path only, registration_form_page.dart's
  // _resolveDiscountStamp additionally competes the registrant's OWN
  // active-Insider tier discount against the first-timer-promo outcome
  // above (best-discount-wins, spec §5/promo_engine.dart's
  // pickBestDiscount) — when the tier discount wins, DiscountSource becomes
  // 'insider_tier' instead, with the SAME DiscountPct/EligibleFee shape
  // (percent off EligibleFee). InsiderCode/FirstTimer are untouched by this
  // — they only ever describe a code THIS registrant entered (referring
  // someone else), never their own tier discount.
  final String insiderCode; // normalized (uppercased); '' when none entered
  final bool? firstTimer; // null until a code was validated

  final double? eligibleFee; // the base fee the promo pct was computed against

  const RegSubmission({
    required this.path,
    required this.answers,
    this.teamId = '',
    this.paid = false,
    this.paidVia = '',
    this.paidAmount,
    this.displayName = '',
    this.submittedAt = 0,
    this.adjustedFee,
    this.discountPct,
    this.discountSource = '',
    this.adjustReason = '',
    this.insiderCode = '',
    this.firstTimer,
    this.eligibleFee,
  });

  /// True when an admin has manually adjusted this submission's fee.
  bool get isAdjusted => adjustedFee != null || discountPct != null;

  Map<String, dynamic> toFirebaseMap() => {
        'Path': path,
        'Answers': answers,
        if (teamId.isNotEmpty) 'TeamId': teamId,
        'Paid': paid,
        if (paidVia.isNotEmpty) 'PaidVia': paidVia,
        if (paidAmount != null) 'PaidAmount': paidAmount,
        'DisplayName': displayName,
        'SubmittedAt': submittedAt,
        if (adjustedFee != null) 'AdjustedFee': adjustedFee,
        if (discountPct != null) 'DiscountPct': discountPct,
        if (discountSource.isNotEmpty) 'DiscountSource': discountSource,
        if (adjustReason.isNotEmpty) 'AdjustReason': adjustReason,
        if (insiderCode.isNotEmpty) 'InsiderCode': insiderCode,
        if (firstTimer != null) 'FirstTimer': firstTimer,
        if (eligibleFee != null) 'EligibleFee': eligibleFee,
      };

  /// Defensive parse; returns null for malformed nodes.
  static RegSubmission? fromFirebase(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['Path']?.toString() ?? '';
    if (path.isEmpty) return null;
    final rawAnswers = raw['Answers'];
    final rawPaidAmount = raw['PaidAmount'];
    final rawAdjustedFee = raw['AdjustedFee'];
    final rawDiscountPct = raw['DiscountPct'];
    final rawEligibleFee = raw['EligibleFee'];
    final rawFirstTimer = raw['FirstTimer'];
    return RegSubmission(
      path: path,
      answers: rawAnswers is Map
          ? rawAnswers.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{},
      teamId: raw['TeamId']?.toString() ?? '',
      paid: raw['Paid'] == true,
      paidVia: raw['PaidVia']?.toString() ?? '',
      paidAmount: rawPaidAmount is num
          ? rawPaidAmount
          : num.tryParse(rawPaidAmount?.toString() ?? ''),
      displayName: raw['DisplayName']?.toString() ?? '',
      submittedAt: int.tryParse(raw['SubmittedAt']?.toString() ?? '') ?? 0,
      adjustedFee: rawAdjustedFee is num
          ? rawAdjustedFee.toDouble()
          : double.tryParse(rawAdjustedFee?.toString() ?? ''),
      discountPct: rawDiscountPct is num
          ? rawDiscountPct.toDouble()
          : double.tryParse(rawDiscountPct?.toString() ?? ''),
      discountSource: raw['DiscountSource']?.toString() ?? '',
      adjustReason: raw['AdjustReason']?.toString() ?? '',
      insiderCode: raw['InsiderCode']?.toString() ?? '',
      firstTimer: rawFirstTimer is bool ? rawFirstTimer : null,
      eligibleFee: rawEligibleFee is num
          ? rawEligibleFee.toDouble()
          : double.tryParse(rawEligibleFee?.toString() ?? ''),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment-owed logic
// ---------------------------------------------------------------------------

/// Whether this submission still owes a payment. Joiners are governed by
/// their team's CodeWaivesPayment flag (L1b passes it in; L1a's individual
/// path never sets it).
///
/// Individuals owe [RegistrationConfig.fee] under 'perPlayer' or 'both' (0
/// under 'teamFee' — nothing is owed until an admin moves them onto a team).
/// Captains (L1b) owe [RegistrationConfig.teamFee] under 'teamFee' or 'both'.
bool paymentOwed({
  required RegistrationConfig config,
  required RegSubmission submission,
  bool codeWaivesPayment = false,
}) {
  if (submission.paid) return false;
  if (submission.path == 'joiner') {
    return config.fee > 0 && !codeWaivesPayment;
  }
  if (submission.path == 'captain') {
    return config.teamFee > 0 &&
        (config.paymentMode == 'teamFee' || config.paymentMode == 'both');
  }
  // individual (and any other/legacy path)
  return config.fee > 0 &&
      (config.paymentMode == 'perPlayer' || config.paymentMode == 'both');
}

// ---------------------------------------------------------------------------
// Profile mapping (well-known keys)
// ---------------------------------------------------------------------------

/// The Users/{uid}/Information field that holds positions for a sport.
/// '' means "don't write positions back" (unknown sport).
String positionsFieldForSport(String sport) {
  switch (sport) {
    case 'Basketball':
      return 'BasketballPosition';
    case 'Flag Football':
      return 'FlagFootballPosition';
    case 'Futsal':
    case 'Soccer':
      return 'FutsalPosition';
    default:
      return '';
  }
}

// ---------------------------------------------------------------------------
// Default template (seed when FormTemplates/default is empty)
// ---------------------------------------------------------------------------

const List<RegQuestion> kDefaultRegQuestions = [
  RegQuestion(
      key: 'firstName', type: 'shortText', label: 'First Name', isRequired: true),
  RegQuestion(
      key: 'lastName', type: 'shortText', label: 'Last Name', isRequired: true),
  RegQuestion(
      key: 'phone', type: 'phone', label: 'Phone Number', isRequired: true),
  RegQuestion(key: 'age', type: 'number', label: 'Age', isRequired: true),
  RegQuestion(
      key: 'height', type: 'height', label: 'Height', isRequired: true),
  RegQuestion(
    key: 'positions',
    type: 'multiChoice',
    label: 'Positions',
    isRequired: true,
    options: ['Goal Keeper', 'Defender', 'Midfielder', 'Striker'],
  ),
  RegQuestion(key: 'comment', type: 'paragraph', label: 'Comment (optional)'),
  RegQuestion(
      key: 'rules',
      type: 'linkAcknowledge',
      label: 'Season Rules',
      isRequired: true),
  RegQuestion(
      key: 'waiver',
      type: 'linkAcknowledge',
      label: 'Waiver Conditions',
      isRequired: true),
];

// ---------------------------------------------------------------------------
// Teams (Registrations/{regId}/Teams/{teamId}) — L1b
// ---------------------------------------------------------------------------

/// Valid RegTeam.status values.
const List<String> kRegTeamStatuses = ['pending', 'approved', 'rejected'];

class RegTeam {
  final String id;
  final String name;
  final String captainUid;
  final String status; // 'pending' | 'approved' | 'rejected'
  final String joinCode; // '' until approved
  final bool codeWaivesPayment; // joiners with this code skip payment
  final int createdAt; // millisecondsSinceEpoch

  const RegTeam({
    required this.id,
    required this.name,
    required this.captainUid,
    this.status = 'pending',
    this.joinCode = '',
    this.codeWaivesPayment = false,
    this.createdAt = 0,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  Map<String, dynamic> toFirebaseMap() => {
        'Name': name,
        'CaptainUid': captainUid,
        'Status': status,
        if (joinCode.isNotEmpty) 'JoinCode': joinCode,
        'CodeWaivesPayment': codeWaivesPayment,
        'CreatedAt': createdAt,
      };

  /// Defensive parse; returns null for malformed nodes.
  static RegTeam? fromNode(String id, Object? raw) {
    if (raw is! Map) return null;
    final name = raw['Name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final rawStatus = raw['Status']?.toString() ?? 'pending';
    return RegTeam(
      id: id,
      name: name,
      captainUid: raw['CaptainUid']?.toString() ?? '',
      status: kRegTeamStatuses.contains(rawStatus) ? rawStatus : 'pending',
      joinCode: raw['JoinCode']?.toString() ?? '',
      codeWaivesPayment: raw['CodeWaivesPayment'] == true,
      createdAt: int.tryParse(raw['CreatedAt']?.toString() ?? '') ?? 0,
    );
  }

  RegTeam copyWith({
    String? name,
    String? captainUid,
    String? status,
    String? joinCode,
    bool? codeWaivesPayment,
    int? createdAt,
  }) =>
      RegTeam(
        id: id,
        name: name ?? this.name,
        captainUid: captainUid ?? this.captainUid,
        status: status ?? this.status,
        joinCode: joinCode ?? this.joinCode,
        codeWaivesPayment: codeWaivesPayment ?? this.codeWaivesPayment,
        createdAt: createdAt ?? this.createdAt,
      );
}

/// Parses a Registrations/{regId}/Teams node into {teamId: team}, skipping
/// malformed entries. {} for null/junk.
Map<String, RegTeam> regTeamsFromNode(Object? raw) {
  final out = <String, RegTeam>{};
  if (raw is Map) {
    raw.forEach((id, value) {
      final team = RegTeam.fromNode(id.toString(), value);
      if (team != null) out[id.toString()] = team;
    });
  }
  return out;
}

/// Team-name hygiene: trim/collapse whitespace + capitalize each word
/// ("  the   boys " -> "The Boys"). Existing capitals are preserved
/// ("LA galaxy" -> "LA Galaxy").
String cleanTeamName(String input) =>
    capitalizeWords(collapseTrailingSpaces(input));

// ---------------------------------------------------------------------------
// Join codes
// ---------------------------------------------------------------------------

/// Confusable-free code alphabet (no I/O/0/1) — the same one the tournament
/// join-code dialog uses (Manager lib/ui/tournaments/manage_teams_page.dart).
const String kJoinCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// The uppercased/trimmed form every code is stored and compared in.
String normalizeJoinCode(String input) => input.trim().toUpperCase();

/// A random [length]-char code. [random] is injected so tests can seed it;
/// UI callers pass Random.secure().
String generateJoinCode(Random random, {int length = 6}) => List.generate(
        length, (_) => kJoinCodeAlphabet[random.nextInt(kJoinCodeAlphabet.length)])
    .join();

/// A random code not present in [taken] (compared normalized). Retries up to
/// 100 times, then falls back to a longer code so the function stays total —
/// collisions over the 32^6 space are practically impossible.
String generateUniqueJoinCode(Random random, Set<String> taken,
    {int length = 6}) {
  final normalizedTaken = taken.map(normalizeJoinCode).toSet();
  for (var i = 0; i < 100; i++) {
    final code = generateJoinCode(random, length: length);
    if (!normalizedTaken.contains(code)) return code;
  }
  return generateJoinCode(random, length: length + 2);
}

/// null when [code] is usable, else the problem to show. Mirrors the
/// tournament dialog's 4-12 rule; [taken] holds every OTHER team's code in
/// the same registration (any casing) for the per-registration uniqueness
/// check.
String? validateJoinCode(String code, {Set<String> taken = const {}}) {
  final c = normalizeJoinCode(code);
  if (c.length < 4 || c.length > 12) return 'Code must be 4-12 characters.';
  if (!RegExp(r'^[A-Z0-9]+$').hasMatch(c)) return 'Letters and numbers only.';
  if (taken.map(normalizeJoinCode).contains(c)) {
    return 'That code is already used by another team.';
  }
  return null;
}

/// Outcome of matching an entered code against a registration's teams.
/// status: 'ok' (approved team found — [team] set), 'notApproved' (the code
/// belongs to a pending/rejected team — [team] set), 'notFound'.
class JoinCodeMatch {
  final String status;
  final RegTeam? team;
  const JoinCodeMatch(this.status, [this.team]);
}

/// Finds the team whose JoinCode matches [input] (compared normalized).
/// An approved team always wins over a non-approved one with the same code.
JoinCodeMatch matchJoinCode(Map<String, RegTeam> teams, String input) {
  final code = normalizeJoinCode(input);
  if (code.isEmpty) return const JoinCodeMatch('notFound');
  RegTeam? nonApproved;
  for (final team in teams.values) {
    if (team.joinCode.isEmpty) continue;
    if (normalizeJoinCode(team.joinCode) != code) continue;
    if (team.isApproved) return JoinCodeMatch('ok', team);
    nonApproved ??= team;
  }
  return nonApproved != null
      ? JoinCodeMatch('notApproved', nonApproved)
      : const JoinCodeMatch('notFound');
}

/// True when another team in [teams] (any status, any id but [teamId])
/// carries [name] modulo case/outer whitespace — the approval dialog warns
/// on duplicates (spec section 7).
bool hasDuplicateTeamName(
    Map<String, RegTeam> teams, String teamId, String name) {
  final needle = name.trim().toLowerCase();
  return teams.entries
      .any((e) => e.key != teamId && e.value.name.trim().toLowerCase() == needle);
}

// ---------------------------------------------------------------------------
// Amount owed
// ---------------------------------------------------------------------------

/// The dollar amount a submission owes right now — 0 whenever [paymentOwed]
/// says nothing is owed. Captains owe [RegistrationConfig.teamFee]; everyone
/// else owes [RegistrationConfig.fee]. The payment screen shows THIS number
/// (a captain must never be shown the per-player fee).
num amountOwed({
  required RegistrationConfig config,
  required RegSubmission submission,
  bool codeWaivesPayment = false,
}) {
  if (!paymentOwed(
      config: config,
      submission: submission,
      codeWaivesPayment: codeWaivesPayment)) {
    return 0;
  }
  return submission.path == 'captain' ? config.teamFee : config.fee;
}
