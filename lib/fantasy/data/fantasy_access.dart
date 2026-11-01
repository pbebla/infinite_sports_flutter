// Paid access (season pass) — the fan app's pure data layer (spec
// 2026-11-01: §3 `Config/Access`, §4 `Access/<uid>`, §6 `AccessClaims`,
// §9 paywall copy). No Flutter/Firebase imports; FantasyService wraps these
// in onValue streams; unit-tested in test/fantasy/fantasy_access_test.dart.
//
// Twin of the server's functions/src/lib/fantasy/access.ts (defaults and
// node shapes are pinned there too — keep them in step).
//
// The fan app never learns WHY someone is active: a granted / grandfathered
// / player record parses to the same "active" as a paid one, and nothing
// here (or on the pay card) names grants, free access or admins.

/// `Config/Access/Mode` — absent = free (today's behaviour).
enum FantasyAccessMode { free, pass }

/// The paywall copy defaults (spec §9 `Copy`), used field by field when the
/// stored copy is absent or blank.
const String kAccessHeadlineDefault = 'Join Infinite Fantasy';
const String kAccessBodyDefault =
    'A season pass for {season} is {amount}. Pay once, play the whole season.';
const String kAccessButtonDefault = 'Get my season pass';

/// The longest claim note the rules accept (`Note` string ≤ 120).
const int kAccessClaimNoteMaxLength = 120;

/// The streamed `Fantasy/<sport>/<season>/Config/Access` block: mode, price,
/// the enabled outside-the-app payment methods and the paywall copy.
class FantasyAccessConfig {
  const FantasyAccessConfig({
    this.mode = FantasyAccessMode.free,
    this.amountDollars = 0,
    this.venmo = true,
    this.zelle = false,
    this.card = true,
    this.headline = kAccessHeadlineDefault,
    this.body = kAccessBodyDefault,
    this.button = kAccessButtonDefault,
  });

  /// Free mode with every default — what an absent block means.
  static const FantasyAccessConfig free = FantasyAccessConfig();

  final FantasyAccessMode mode;

  /// Whole dollars or .50 (the Manager validates > 0 in pass mode).
  final double amountDollars;

  /// `Methods/{Venmo,Zelle,Card}` — which pay buttons the card shows.
  final bool venmo;
  final bool zelle;
  final bool card;

  /// `Copy/{Headline,Body,Button}` with `{season}` / `{amount}`
  /// placeholders (filled by [headlineFor] / [bodyFor] / [buttonFor]).
  final String headline;
  final String body;
  final String button;

  /// The gate applies: pass mode (the rules gate on `Mode` alone).
  bool get isPass => mode == FantasyAccessMode.pass;

  /// "$10" / "$10.50".
  String get priceLabel => formatAccessDollars(amountDollars);

  String headlineFor({required String sport, required String season}) =>
      _fill(headline, sport, season);
  String bodyFor({required String sport, required String season}) =>
      _fill(body, sport, season);
  String buttonFor({required String sport, required String season}) =>
      _fill(button, sport, season);

  String _fill(String text, String sport, String season) => fillAccessCopy(
      text,
      season: accessSeasonLabel(sport, season),
      amount: priceLabel);
}

/// Tolerant parse of the `Config/Access` block: absent / malformed → free
/// with every default; a bad field falls back on its own, never the block.
FantasyAccessConfig accessConfigFromNode(Object? node) {
  if (node is! Map) return FantasyAccessConfig.free;
  final methods = node['Methods'];
  bool method(String key, bool fallback) {
    if (methods is! Map) return fallback;
    final v = methods[key];
    return v is bool ? v : fallback;
  }

  final copy = node['Copy'];
  String text(String key, String fallback) {
    if (copy is! Map) return fallback;
    final v = copy[key];
    if (v is! String) return fallback;
    final trimmed = v.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  return FantasyAccessConfig(
    mode: node['Mode'] == 'pass'
        ? FantasyAccessMode.pass
        : FantasyAccessMode.free,
    amountDollars: _dollars(node['AmountDollars']),
    venmo: method('Venmo', true),
    zelle: method('Zelle', false),
    card: method('Card', true),
    headline: text('Headline', kAccessHeadlineDefault),
    body: text('Body', kAccessBodyDefault),
    button: text('Button', kAccessButtonDefault),
  );
}

/// A finite, non-negative dollar amount; anything else reads as 0.
double _dollars(Object? raw) {
  if (raw is! num) return 0;
  final d = raw.toDouble();
  if (!d.isFinite || d < 0) return 0;
  return d;
}

/// `Access/<uid>/Status` plus "no record" (none).
enum FantasyAccessStatus { none, pending, active, revoked }

/// One `Fantasy/<sport>/<season>/Access/<uid>` record (server/admin-written,
/// spec §4). The fan app reads only what the card needs.
class FantasyAccessRecord {
  const FantasyAccessRecord({
    required this.status,
    required this.via,
    required this.amountCents,
    required this.paidAt,
  });

  final FantasyAccessStatus status;

  /// 'card' | 'venmo' | 'zelle' | 'granted' | 'player' | 'grandfathered'
  /// ('' when absent). Never shown to the fan.
  final String via;
  final int amountCents;

  /// The activation instant (epoch ms); null while pending.
  final int? paidAt;

  bool get isActive => status == FantasyAccessStatus.active;
}

/// null when the node is absent / malformed / carries an unknown Status —
/// all of which mean "no access record" (none), never a crash.
FantasyAccessRecord? accessRecordFromNode(Object? node) {
  if (node is! Map) return null;
  final status = switch (node['Status']) {
    'active' => FantasyAccessStatus.active,
    'pending' => FantasyAccessStatus.pending,
    'revoked' => FantasyAccessStatus.revoked,
    _ => null,
  };
  if (status == null) return null;
  final cents = node['AmountCents'];
  final paidAt = node['PaidAt'];
  return FantasyAccessRecord(
    status: status,
    via: node['Via'] is String ? node['Via'] as String : '',
    amountCents: cents is num && cents.isFinite ? cents.toInt() : 0,
    paidAt: paidAt is num && paidAt.isFinite ? paidAt.toInt() : null,
  );
}

/// What the hub's Access feed emits: the record (null = none) plus a
/// `degraded` flag — error ≠ fact: when the read FAILED before any value was
/// known, the card shows a retry line, never the pay methods as if unpaid.
class FantasyAccessState {
  const FantasyAccessState({this.record, this.degraded = false});

  /// No record, read fine (free mode, or an unpaid fan).
  static const FantasyAccessState none = FantasyAccessState();

  final FantasyAccessRecord? record;
  final bool degraded;

  FantasyAccessStatus get status => record?.status ?? FantasyAccessStatus.none;
  bool get isActive => record?.isActive ?? false;
}

/// [accessRecordFromNode] wrapped as a (non-degraded) state.
FantasyAccessState accessStateFromNode(Object? node) =>
    FantasyAccessState(record: accessRecordFromNode(node));

/// The outside-the-app methods a fan can claim ("I sent it").
enum FantasyAccessMethod {
  venmo('venmo', 'Venmo'),
  zelle('zelle', 'Zelle');

  const FantasyAccessMethod(this.key, this.label);

  /// The `Method` value the rules validate.
  final String key;
  final String label;
}

/// The `AccessClaims/<uid>/<pushKey>` node an "I sent it" tap writes (spec
/// §6; rules: Method ∈ {venmo, zelle}, AmountDollars number ≥ 0, At number,
/// Note string ≤ 120). [at] is `ServerValue.timestamp` in production.
/// Whole dollars write as an integer.
Map<String, Object?> accessClaimPayload({
  required FantasyAccessMethod method,
  required double amountDollars,
  required String note,
  required Object at,
}) {
  if (!amountDollars.isFinite || amountDollars < 0) {
    throw ArgumentError.value(
        amountDollars, 'amountDollars', 'must be a non-negative amount');
  }
  final whole = amountDollars == amountDollars.roundToDouble();
  return {
    'Method': method.key,
    'AmountDollars': whole ? amountDollars.toInt() : amountDollars,
    'Note': _clipNote(note),
    'At': at,
  };
}

/// The Venmo / claim note: `Fantasy <sport> S<season> <display name>`
/// (a blank name is simply left off), clipped to the rules' 120 chars.
String accessClaimNote({
  required String sport,
  required String season,
  required String displayName,
}) =>
    _clipNote('Fantasy $sport S$season ${displayName.trim()}'.trim());

String _clipNote(String note) {
  final trimmed = note.trim();
  return trimmed.length <= kAccessClaimNoteMaxLength
      ? trimmed
      : trimmed.substring(0, kAccessClaimNoteMaxLength);
}

/// The `createFantasyCheckoutSession` callable's result: `{url}` → the
/// Checkout Uri to open; `{alreadyActive: true}` → null (the card is about
/// to dismiss on its own — the live stream flips it). Anything else is an
/// error, never a blank launch.
Uri? checkoutUrlFromResult(Object? data) {
  if (data is! Map) throw StateError('Unexpected checkout result: $data');
  if (data['alreadyActive'] == true) return null;
  final raw = data['url'];
  if (raw is! String || raw.trim().isEmpty) {
    throw StateError('Checkout result carried no url');
  }
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    throw StateError('Checkout result url is not a web link: $raw');
  }
  return uri;
}

/// "$10" for whole dollars, "$10.50" otherwise (the fan-facing price).
String formatAccessDollars(double dollars) =>
    dollars == dollars.roundToDouble()
        ? '\$${dollars.toInt()}'
        : '\$${dollars.toStringAsFixed(2)}';

/// "Futsal Season 16" — the `{season}` placeholder's value (server parity:
/// `seasonLabel`).
String accessSeasonLabel(String sport, String season) =>
    '$sport Season $season';

/// Fills `{season}` and `{amount}`; unknown placeholders stay literal
/// (server parity: `fillTemplate`).
String fillAccessCopy(String text,
        {required String season, required String amount}) =>
    text.replaceAll('{season}', season).replaceAll('{amount}', amount);
