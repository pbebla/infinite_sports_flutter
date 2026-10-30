// Fantasy P3a Task 0 — seeds `Fantasy/<sport>/<season>/{Config, Players}`
// from a real season's lineups + per-game stats using the engine's own
// opening-price math. Pure Dart (dart:io HttpClient over the RTDB REST API),
// no Flutter — runnable from the repo root:
//
//   dart run tool/seed_fantasy.dart <sport> <season> [adminToken] [--dry]
//
//   dart run tool/seed_fantasy.dart Futsal 15 --dry        # read-only summary
//   dart run tool/seed_fantasy.dart Futsal 15 <token>      # seed the test bed
//
// --dry prints the full summary (players per position, price spread, flagged
// entries) and performs NO writes; a real run additionally PUTs the Config and
// Players nodes with the admin OAuth access token in an
// `Authorization: Bearer` header (never in the URL). Launch data for a future
// season is a re-run of this tool against that season (plan P3a).
//
// All pure logic (position mapping, aggregation, pricing, node shapes) lives
// in seed_fantasy_logic.dart and is unit-tested in
// test/fantasy/seed_logic_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';

import 'seed_fantasy_logic.dart';

const _host = 'infinite-sports-app.firebaseio.com';

Future<Object?> _get(HttpClient client, String path) async {
  final uri = Uri.https(_host, '$path.json');
  final req = await client.getUrl(uri);
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) {
    throw HttpException('GET $uri -> ${res.statusCode}: $body');
  }
  return jsonDecode(body);
}

Future<void> _put(
    HttpClient client, String path, String token, Object value) async {
  // The token rides in the Authorization header (RTDB REST accepts OAuth2
  // Bearer access tokens) — never in the URL, which logs and errors echo.
  final uri = Uri.https(_host, '$path.json');
  final req = await client.putUrl(uri);
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(value));
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) {
    throw HttpException('PUT $_host/$path.json -> ${res.statusCode}: $body');
  }
}

String _money(int tenths) => '\$${(tenths / 10).toStringAsFixed(1)}M';

Future<void> main(List<String> args) async {
  final flags = args.where((a) => a.startsWith('--')).toSet();
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final dry = flags.contains('--dry');
  if (positional.length < 2 || (!dry && positional.length < 3)) {
    stderr.writeln(
        'usage: dart run tool/seed_fantasy.dart <sport> <season> [adminToken] [--dry]');
    exit(64);
  }
  final sport = positional[0];
  final season = positional[1];
  final token = positional.length > 2 ? positional[2] : '';
  final cfg = FantasyConfig.futsalDefault();

  final client = HttpClient();
  try {
    // ── Reads ────────────────────────────────────────────────────────────
    stdout.writeln('Reading $sport/$season …');
    final lineupsNode = await _get(client, '$sport/$season/Line Ups');
    final dateNode = await _get(client, '$sport/$season/Date');
    final lineups = parseLineups(lineupsNode);
    if (lineups.isEmpty) {
      stderr.writeln('No lineups found at $sport/$season/Line Ups — aborting.');
      exit(1);
    }

    // Registration positions, one REST read per linked player.
    final positionByName = <String, FantasyPosition>{};
    final defaulted = <String>[]; // no/unreadable registration → ATT default
    for (final entry in lineups) {
      Object? raw;
      if (entry.uid != null) {
        raw = await _get(
            client, 'Users/${entry.uid}/Information/${sport}Position');
      }
      final rawString = raw?.toString();
      if (rawString == null || rawString.trim().isEmpty) {
        defaulted.add(entry.name);
      }
      positionByName[entry.name] = mapRegistrationPosition(rawString);
    }

    // Profile photos (P3b Task 3): the lineup UID link resolves each player
    // to PublicProfiles/<uid>/ProfileUrl (the server-maintained public
    // mirror — the same source the fan app's rosters read). No UID link or
    // no public photo → photoUrl omitted, the chip renders initials.
    final photoUrlByName = <String, String>{};
    for (final entry in lineups) {
      if (entry.uid == null) continue;
      try {
        final raw =
            await _get(client, 'PublicProfiles/${entry.uid}/ProfileUrl');
        final url = raw?.toString().trim() ?? '';
        if (url.isNotEmpty) photoUrlByName[entry.name] = url;
      } on HttpException {
        // Unreadable profile node — photo simply omitted for this player.
      }
    }

    // ── Engine replay: season points → opening prices ────────────────────
    final rosterByTeam = <String, Set<String>>{};
    for (final entry in lineups) {
      rosterByTeam.putIfAbsent(entry.teamName, () => <String>{}).add(entry.name);
    }
    final aggregate = seasonPointsByPlayer(
      dateNode: dateNode,
      positionByName: positionByName,
      rosterByTeam: rosterByTeam,
      cfg: cfg,
    );
    final prices = buildOpeningPrices(
      positionByName: positionByName,
      pointsByName: aggregate.pointsByName,
      cfg: cfg,
    );
    final playersNode = buildPlayersNode(
      lineups: lineups,
      positionByName: positionByName,
      priceByName: prices,
      cfg: cfg,
      photoUrlByName: photoUrlByName,
    );
    final configNode = buildConfigNode(lockOverride: 'open');

    // ── Summary ──────────────────────────────────────────────────────────
    stdout.writeln('');
    stdout.writeln('── Seed summary: Fantasy/$sport/$season ──');
    stdout.writeln('Players: ${lineups.length} across '
        '${rosterByTeam.length} teams');
    for (final pos in FantasyPosition.values) {
      final names = positionByName.entries
          .where((e) => e.value == pos)
          .map((e) => e.key)
          .toList()
        ..sort((a, b) => (prices[b] ?? 0).compareTo(prices[a] ?? 0));
      if (names.isEmpty) {
        stdout.writeln('  ${pos.db}: 0 players');
        continue;
      }
      final tenths = names.map((n) => prices[n] ?? cfg.rookiePriceTenths);
      final lo = tenths.reduce((a, b) => a < b ? a : b);
      final hi = tenths.reduce((a, b) => a > b ? a : b);
      stdout.writeln('  ${pos.db}: ${names.length} players, '
          '${_money(lo)}–${_money(hi)}');
      for (final n in names.take(3)) {
        stdout.writeln('    ${_money(prices[n]!)}  $n  '
            '(${aggregate.pointsByName[n]?.toStringAsFixed(0) ?? 'rookie'} pts)');
      }
      if (names.length > 3) {
        final n = names.last;
        stdout.writeln('    …');
        stdout.writeln('    ${_money(prices[n]!)}  $n  '
            '(${aggregate.pointsByName[n]?.toStringAsFixed(0) ?? 'rookie'} pts)');
      }
    }
    final ineligible =
        lineups.where((e) => isGuestName(e.name)).map((e) => e.name).toList();
    stdout.writeln('Ineligible (guests): '
        '${ineligible.isEmpty ? 'none' : ineligible.join(', ')}');
    stdout.writeln('No registration position (defaulted to ATT): '
        '${defaulted.isEmpty ? 'none' : defaulted.join(', ')}');
    stdout.writeln('Activity names with no lineup entry (NOT seeded): '
        '${aggregate.activityOnlyNames.isEmpty ? 'none' : aggregate.activityOnlyNames.join(', ')}');
    final linked = lineups.where((e) => e.uid != null).length;
    stdout.writeln('Photos: ${photoUrlByName.length} of ${lineups.length} '
        'players got a photoUrl ($linked have a UID link; '
        'PublicProfiles/<uid>/ProfileUrl)');
    stdout.writeln(
        'Config: futsalDefault + lockOverride=open (budget ${_money(cfg.budgetTenths)}, '
        'prices ${_money(cfg.priceMinTenths)}–${_money(cfg.priceMaxTenths)})');

    // ── Writes ───────────────────────────────────────────────────────────
    if (dry) {
      stdout.writeln('');
      stdout.writeln('--dry: no writes performed.');
      return;
    }
    stdout.writeln('');
    stdout.writeln('Writing Fantasy/$sport/$season/Config …');
    await _put(client, 'Fantasy/$sport/$season/Config', token, configNode);
    stdout.writeln('Writing Fantasy/$sport/$season/Players '
        '(${playersNode.length} players) …');
    await _put(client, 'Fantasy/$sport/$season/Players', token, playersNode);
    stdout.writeln('Done.');
  } finally {
    client.close(force: true);
  }
}
