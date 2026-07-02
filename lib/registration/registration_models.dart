// Pure registration-engine models + helpers (Leagues epic L1, phase L1a).
//
// NO Flutter/Firebase imports — unit-tested directly. This file is
// intentionally DUPLICATED byte-for-byte in both repos (the apps share no
// code; precedent: trophy/tournament models). Keep the copies identical:
//   Manager: lib/models/registration_models.dart
//   Fan:     lib/registration/registration_models.dart

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
  final String paidVia; // '' | 'team code' | 'card' | ...
  final String displayName; // account display name at submit time
  final int submittedAt; // millisecondsSinceEpoch

  const RegSubmission({
    required this.path,
    required this.answers,
    this.teamId = '',
    this.paid = false,
    this.paidVia = '',
    this.displayName = '',
    this.submittedAt = 0,
  });

  Map<String, dynamic> toFirebaseMap() => {
        'Path': path,
        'Answers': answers,
        if (teamId.isNotEmpty) 'TeamId': teamId,
        'Paid': paid,
        if (paidVia.isNotEmpty) 'PaidVia': paidVia,
        'DisplayName': displayName,
        'SubmittedAt': submittedAt,
      };

  /// Defensive parse; returns null for malformed nodes.
  static RegSubmission? fromFirebase(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['Path']?.toString() ?? '';
    if (path.isEmpty) return null;
    final rawAnswers = raw['Answers'];
    return RegSubmission(
      path: path,
      answers: rawAnswers is Map
          ? rawAnswers.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{},
      teamId: raw['TeamId']?.toString() ?? '',
      paid: raw['Paid'] == true,
      paidVia: raw['PaidVia']?.toString() ?? '',
      displayName: raw['DisplayName']?.toString() ?? '',
      submittedAt: int.tryParse(raw['SubmittedAt']?.toString() ?? '') ?? 0,
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
      key: 'height',
      type: 'shortText',
      label: "Height (e.g. 5'10)",
      isRequired: true),
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
