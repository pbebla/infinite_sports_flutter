// The My Leagues scope of the Leaderboards tab (P3d, spec §10): the
// mini-leagues the manager belongs to (streamed MiniLeagues filtered
// client-side), each with member count and the manager's rank inside
// (computed from Overall totals filtered to members); a Create flow (name →
// auto-generated 6-char code shown BIG with a copy button) and a Join flow
// (code input with a PASTE button, live lookup, league PREVIEW before
// joining). Opening a league shows the same ranked-rows UI scoped to its
// members plus a "Share code" row (copy + system share).
//
// League detail renders INLINE (not pushed) so the rows stay live off the
// parent tab's streams. Dialogs are StatefulWidgets owning their own
// controllers (house rule: never dispose a controller right after
// `await showDialog` — see livestream_link_dialog.dart).
//
// House rules: theme-safe both modes via colorScheme + the fantasy accent;
// names wrap, never underlined; glass-navbar clearance; initials avatars.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_rows.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/misc/public_profiles.dart';
import 'package:infinite_sports_flutter/misc/share_card_service.dart';
import 'package:share_plus/share_plus.dart' show ShareParams;
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';

class MiniLeaguesView extends StatefulWidget {
  const MiniLeaguesView({
    super.key,
    required this.leagues,
    required this.overall,
    required this.managers,
    required this.profiles,
    required this.selfUid,
    required this.onOpenManager,
    required this.onCreateLeague,
    required this.onJoinLeague,
    this.copyText,
    this.shareText,
    this.readClipboard,
    this.codeGenerator,
  });

  /// ALL streamed mini-leagues (membership filters client-side; the join
  /// lookup needs the full list — codes are public by design).
  final List<FantasyMiniLeague> leagues;

  final List<FantasyLeaderboardEntry> overall;
  final Map<String, FantasyManager> managers;
  final Map<String, PublicProfile> profiles;
  final String selfUid;

  /// Row tap inside a league → the manager squad viewer (the tab owns it).
  final void Function(LeaderboardRowData row) onOpenManager;

  /// FantasyService.createMiniLeague / joinMiniLeague in production.
  final Future<void> Function(String name, String code) onCreateLeague;
  final Future<void> Function(String leagueId) onJoinLeague;

  /// Test seams — platform-channel touches (clipboard, share sheet) aren't
  /// available in widget tests. [shareText] receives the finished
  /// [ShareParams] (text plus the iPad popover anchor).
  final void Function(String text)? copyText;
  final ShareSheet? shareText;
  final Future<String?> Function()? readClipboard;

  /// Deterministic code source for tests; production generates fresh ones.
  final String Function()? codeGenerator;

  @override
  State<MiniLeaguesView> createState() => _MiniLeaguesViewState();
}

class _MiniLeaguesViewState extends State<MiniLeaguesView> {
  /// Open league detail (inline — stays live off the parent's streams).
  String? _openLeagueId;

  void _copy(String text) {
    final override = widget.copyText;
    if (override != null) {
      override(text);
    } else {
      Clipboard.setData(ClipboardData(text: text));
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Code copied.')));
  }

  /// [buttonContext] is the tapped Share button's own context: it anchors
  /// the iPad share popover (share_plus rejects a share without an origin).
  void _share(BuildContext buttonContext, FantasyMiniLeague league) {
    final message = 'Join my Infinite Fantasy mini-league "${league.name}" '
        'with code ${league.code} — Fantasy › Leaderboards › My Leagues in '
        'the Infinite Sports app!';
    final sheet = widget.shareText ?? openShareSheet;
    sheet(ShareParams(
      text: message,
      sharePositionOrigin: shareOriginFor(buttonContext),
    ));
  }

  Future<void> _openCreate() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateLeagueDialog(
        onCreate: widget.onCreateLeague,
        generateCode: widget.codeGenerator ?? generateMiniLeagueCode,
        onCopy: _copy,
      ),
    );
  }

  Future<void> _openJoin() async {
    final joined = await showDialog<FantasyMiniLeague>(
      context: context,
      builder: (_) => _JoinLeagueDialog(
        // Live lookup: reads the parent's CURRENT list on every keystroke.
        lookup: (raw) => findMiniLeagueByCode(widget.leagues, raw),
        selfUid: widget.selfUid,
        onJoin: (league) => widget.onJoinLeague(league.id),
        readClipboard: widget.readClipboard ??
            () async =>
                (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      ),
    );
    if (joined != null && mounted) {
      setState(() => _openLeagueId = joined.id);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Joined ${joined.name}!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.selfUid.isEmpty) {
      return _EmptyCard(
        key: const ValueKey('mini_leagues_signed_out'),
        icon: Icons.group_outlined,
        message: 'Sign in to create or join mini-leagues with your friends.',
      );
    }

    final openLeague = _openLeagueId == null
        ? null
        : widget.leagues.where((l) => l.id == _openLeagueId).firstOrNull;
    if (openLeague != null) return _leagueDetail(context, openLeague);

    final mine = leaguesForMember(widget.leagues, widget.selfUid);
    return ListView(
      key: const ValueKey('mini_leagues_list'),
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                key: const ValueKey('mini_league_create'),
                onPressed: _openCreate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create a league'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                key: const ValueKey('mini_league_join'),
                onPressed: _openJoin,
                icon: const Icon(Icons.tag, size: 18),
                label: const Text('Join with a code'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (mine.isEmpty)
          _EmptyCard(
            key: const ValueKey('mini_leagues_empty'),
            icon: Icons.emoji_events_outlined,
            message: 'No mini-leagues yet — create one and share the code '
                'with your friends, or join theirs.',
          )
        else
          for (final league in mine) _leagueCard(context, league, scheme),
      ],
    );
  }

  Widget _leagueCard(
      BuildContext context, FantasyMiniLeague league, ColorScheme scheme) {
    final rows = composeMiniLeagueRows(
      league: league,
      overall: widget.overall,
      managers: widget.managers,
      profiles: widget.profiles,
      selfUid: widget.selfUid,
    );
    final rank = miniLeagueRankOf(widget.selfUid, rows);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('mini_league_card_${league.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _openLeagueId = league.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        league.name,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${league.memberCount} '
                        '${league.memberCount == 1 ? 'member' : 'members'}'
                        '${rank == null ? '' : ' · You\'re #$rank'}',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _leagueDetail(BuildContext context, FantasyMiniLeague league) {
    final scheme = Theme.of(context).colorScheme;
    final rows = composeMiniLeagueRows(
      league: league,
      overall: widget.overall,
      managers: widget.managers,
      profiles: widget.profiles,
      selfUid: widget.selfUid,
    );
    return Column(
      key: ValueKey('mini_league_detail_${league.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 0),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('mini_league_back'),
                tooltip: 'Back to your leagues',
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => setState(() => _openLeagueId = null),
              ),
              Expanded(
                child: Text(
                  league.name,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        // The "Share code" row: code + copy + system share.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Code  ${league.code}',
                    key: const ValueKey('mini_league_code_row'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('mini_league_copy'),
                  tooltip: 'Copy code',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.copy,
                      size: 18, color: fantasyAccent(context)),
                  onPressed: () => _copy(league.code),
                ),
                // Builder: the share popover anchors to THIS button.
                Builder(
                  builder: (buttonContext) => IconButton(
                    key: const ValueKey('mini_league_share'),
                    tooltip: 'Share code',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.share,
                        size: 18, color: fantasyAccent(context)),
                    onPressed: () => _share(buttonContext, league),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Same ranked-rows UI, scoped to the league's members.
        Expanded(
          child: RankedLeaderboardList(
            rows: rows,
            showMovement: false,
            onRowTap: widget.onOpenManager,
          ),
        ),
      ],
    );
  }
}

/// Create flow: name in, then the fresh code shown BIG with a copy button.
/// One dialog, two phases — the StatefulWidget owns its controller (house
/// rule) and the code reveal replaces the form on success.
class _CreateLeagueDialog extends StatefulWidget {
  const _CreateLeagueDialog({
    required this.onCreate,
    required this.generateCode,
    required this.onCopy,
  });

  final Future<void> Function(String name, String code) onCreate;
  final String Function() generateCode;
  final void Function(String code) onCopy;

  @override
  State<_CreateLeagueDialog> createState() => _CreateLeagueDialogState();
}

class _CreateLeagueDialogState extends State<_CreateLeagueDialog> {
  final TextEditingController _name = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Set on success — flips the dialog to the code reveal.
  String? _createdCode;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _nameOk {
    final n = _name.text.trim();
    return n.length >= 3 && n.length <= 30;
  }

  Future<void> _create() async {
    final code = widget.generateCode();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCreate(_name.text.trim(), code);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _createdCode = code;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't create the league — try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final created = _createdCode;
    if (created != null) {
      return AlertDialog(
        title: Text(_name.text.trim(), softWrap: true),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your league is live! Share this code — friends join from '
              'Leaderboards › My Leagues.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text(
              created,
              key: const ValueKey('created_league_code'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                color: fantasyAccent(context),
              ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              key: const ValueKey('created_league_copy'),
              onPressed: () => widget.onCopy(created),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy code'),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('created_league_done'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Create a mini-league'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('create_league_name'),
            controller: _name,
            autofocus: true,
            maxLength: 30,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'League name',
              helperText: '3–30 characters',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              softWrap: true,
              style: TextStyle(fontSize: 12.5, color: fantasyDownRed(context)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('create_league_confirm'),
          onPressed: _nameOk && !_busy ? _create : null,
          child: Text(_busy ? 'Creating…' : 'Create'),
        ),
      ],
    );
  }
}

/// Join flow: 6-char input with a PASTE button, live lookup over the
/// streamed leagues, a league PREVIEW card, then Join (spec §10 adopted).
class _JoinLeagueDialog extends StatefulWidget {
  const _JoinLeagueDialog({
    required this.lookup,
    required this.selfUid,
    required this.onJoin,
    required this.readClipboard,
  });

  final FantasyMiniLeague? Function(String raw) lookup;
  final String selfUid;
  final Future<void> Function(FantasyMiniLeague league) onJoin;
  final Future<String?> Function() readClipboard;

  @override
  State<_JoinLeagueDialog> createState() => _JoinLeagueDialogState();
}

class _JoinLeagueDialogState extends State<_JoinLeagueDialog> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final text = await widget.readClipboard();
    if (!mounted || text == null || text.trim().isEmpty) return;
    setState(() => _code.text = normalizeMiniLeagueCode(text));
  }

  Future<void> _join(FantasyMiniLeague league) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onJoin(league);
      if (!mounted) return;
      Navigator.pop(context, league);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't join — try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final league = widget.lookup(_code.text);
    final complete = isCompleteMiniLeagueCode(_code.text);
    final alreadyIn = league != null && league.hasMember(widget.selfUid);

    return AlertDialog(
      title: const Text('Join a mini-league'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('join_league_code'),
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '6-character code',
              suffixIcon: TextButton(
                key: const ValueKey('join_league_paste'),
                onPressed: _paste,
                child: const Text('PASTE'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // The live PREVIEW before joining.
          if (league != null)
            Container(
              key: ValueKey('join_league_preview_${league.id}'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: fantasyAccent(context).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: fantasyAccent(context).withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    league.name,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${league.memberCount} '
                    '${league.memberCount == 1 ? 'member' : 'members'}'
                    '${alreadyIn ? " · You're already in this league" : ''}',
                    softWrap: true,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else if (complete)
            Text(
              'No league found with that code.',
              key: const ValueKey('join_league_not_found'),
              softWrap: true,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              softWrap: true,
              style: TextStyle(fontSize: 12.5, color: fantasyDownRed(context)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('join_league_confirm'),
          onPressed: league != null && !alreadyIn && !_busy
              ? () => _join(league)
              : null,
          child: Text(_busy ? 'Joining…' : 'Join'),
        ),
      ],
    );
  }
}

/// Shared friendly empty/info card for this scope.
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
