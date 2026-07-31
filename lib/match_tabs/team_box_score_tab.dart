import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/match_tabs/box_score_columns.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/profile/open_player_profile.dart';

/// Per-team box score (Match Box Score spec, 2026-07-28) — one tab per team
/// on BOTH match pages, showing that team's players and their stats for
/// THIS match only. Row identity (photo/name/number) stays frozen on the
/// left while stat columns swipe horizontally; both panes live in the same
/// vertical scroll view, so rows align without controller syncing.
class TeamBoxScoreTab extends StatefulWidget {
  final List<TournamentPlayer> roster;

  /// WHOLE-match per-player tallies (both teams, keyed by player name) —
  /// the auto-hide filter must see both teams so the two team tabs always
  /// render the same column set.
  final Map<String, MatchPlayerTally> tallies;

  /// The sport's full column defs (pre-auto-hide), from [boxScoreColumnsFor].
  final List<BoxScoreColumn> columns;

  /// Test seam (insiders_leaderboard_page convention): replaces
  /// [openPlayerProfileById] so widget tests stay Firebase-free.
  final Future<void> Function(BuildContext context,
      {String? uid, required String name})? openProfileOverride;

  const TeamBoxScoreTab({
    super.key,
    required this.roster,
    required this.tallies,
    required this.columns,
    this.openProfileOverride,
  });

  @override
  State<TeamBoxScoreTab> createState() => _TeamBoxScoreTabState();
}

class _TeamBoxScoreTabState extends State<TeamBoxScoreTab> {
  // Tall enough for a two-line name (owner rule: long player names wrap,
  // never ellipsize — all leagues + tournaments). Shared by the identity
  // and stat panes so their rows stay aligned.
  static const double _rowHeight = 52;
  static const double _headerHeight = 36;
  static const double _identityWidth = 168;

  /// null = default sort (primary stat, best first); 'name' = alphabetical.
  String? _sortKey;
  bool _ascending = false;

  // Visible columns + row order are cached until the live match data (new
  // tallies/roster instances) or the sort state changes — never recomputed
  // per frame in build (the tournamentdetail.dart lag-fix rule).
  List<BoxScoreColumn>? _visible;
  List<TournamentPlayer>? _rows;

  @override
  void didUpdateWidget(TeamBoxScoreTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tallies, widget.tallies) ||
        !identical(oldWidget.columns, widget.columns) ||
        !identical(oldWidget.roster, widget.roster)) {
      _visible = null;
      _rows = null;
    }
  }

  List<BoxScoreColumn> get _visibleColumns =>
      _visible ??= visibleColumns(widget.columns, widget.tallies.values);

  /// The header currently driving the sort ('name' when the match has no
  /// visible stat columns — the empty state lists the roster A-Z).
  String get _activeKey =>
      _sortKey ??
      (_visibleColumns.isEmpty ? 'name' : _visibleColumns.first.key);

  BoxScoreColumn? get _sortColumn {
    if (_activeKey == 'name') return null;
    final cols = _visibleColumns;
    return cols.firstWhere((c) => c.key == _activeKey,
        orElse: () => cols.first);
  }

  List<TournamentPlayer> get _sortedRows => _rows ??= sortedBoxScoreRows(
        widget.roster,
        widget.tallies,
        column: _sortColumn,
        // Empty state has no headers to tap — fixed A-Z.
        ascending: _visibleColumns.isEmpty ? true : _ascending,
      );

  void _onHeaderTap(String key) {
    setState(() {
      if (_activeKey == key) {
        _ascending = !_ascending;
      } else {
        _sortKey = key;
        // Stats open best-first (desc); names open A-Z (asc).
        _ascending = key == 'name';
      }
      _rows = null;
    });
  }

  void _openProfile(BuildContext context, TournamentPlayer p) {
    final open = widget.openProfileOverride ?? openPlayerProfileById;
    open(context, uid: p.uid, name: p.name);
  }

  double _columnWidth(BoxScoreColumn c) =>
      c.label.length <= 3 ? 48 : 24.0 + c.label.length * 8;

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  /// FotMob-style row avatar: roster photo when present, initials fallback
  /// (league lineups carry no player photos).
  Widget _avatar(BuildContext context, TournamentPlayer p) {
    final scheme = Theme.of(context).colorScheme;
    final initials = Text(
      _initials(p.name),
      style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: scheme.onSurfaceVariant),
    );
    final url = p.photoUrl;
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: 14,
        backgroundColor: scheme.surfaceContainerHighest,
        child: initials,
      );
    }
    return CircleAvatar(
      radius: 14,
      backgroundColor: scheme.surfaceContainerHighest,
      foregroundImage: CachedNetworkImageProvider(url),
      onForegroundImageError: (_, __) {},
      child: initials,
    );
  }

  Widget _sortIndicator(BuildContext context, String key) {
    if (_activeKey != key) return const SizedBox.shrink();
    return Icon(
      _ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
      size: 16,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  Widget _nameHeader(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return InkWell(
      onTap: () => _onHeaderTap('name'),
      child: SizedBox(
        height: _headerHeight,
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              Text('Player',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: muted)),
              _sortIndicator(context, 'name'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statHeader(BuildContext context, BoxScoreColumn c) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return InkWell(
      onTap: () => _onHeaderTap(c.key),
      child: SizedBox(
        width: _columnWidth(c),
        height: _headerHeight,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: muted)),
                _sortIndicator(context, c.key),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Frozen-left cell: photo, name, jersey number. Names stay undecorated —
  /// tappable names are never underlined (owner style rule).
  Widget _identityRow(BuildContext context, TournamentPlayer p) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openProfile(context, p),
      child: SizedBox(
        height: _rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _avatar(context, p),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.name,
                  style:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  // Wrap long names to a second line (owner rule); ellipsis
                  // only guards truly pathological 3-line names.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if ((p.number ?? '').isNotEmpty) ...[
                const SizedBox(width: 4),
                Text('#${p.number}',
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.5))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(
      BuildContext context, TournamentPlayer p, List<BoxScoreColumn> visible) {
    final scheme = Theme.of(context).colorScheme;
    final t = widget.tallies[p.name];
    return InkWell(
      onTap: () => _openProfile(context, p),
      child: SizedBox(
        height: _rowHeight,
        child: Row(
          children: [
            for (final c in visible)
              SizedBox(
                width: _columnWidth(c),
                child: Center(
                  child: Builder(builder: (context) {
                    final v = c.valueOf(t);
                    final has = v != null && v != 0;
                    return Text(
                      v == null ? '-' : '$v${c.suffix}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                        color: has
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: 0.35),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mutedNote(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    if (widget.roster.isEmpty) {
      return SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: _mutedNote(context, 'No roster data'),
      );
    }

    final visible = _visibleColumns;
    final rows = _sortedRows;
    // Total stat-pane width — the header divider can't size itself inside
    // the unbounded horizontal scroll view.
    final statWidth =
        visible.fold<double>(0, (sum, c) => sum + _columnWidth(c));

    // Zero recorded stats: roster rows with a muted note — never a blank tab.
    if (visible.isEmpty) {
      return SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _mutedNote(context, 'No stats recorded yet'),
            const Divider(height: 1, thickness: 1),
            // Rows read Theme.of(context) — Builder keeps the context live
            // across theme toggles (itemBuilder staleness rule).
            for (final p in rows)
              Builder(builder: (context) => _identityRow(context, p)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Frozen identity pane.
          SizedBox(
            width: _identityWidth,
            child: Column(
              children: [
                _nameHeader(context),
                const Divider(height: 1, thickness: 1),
                for (final p in rows)
                  Builder(builder: (context) => _identityRow(context, p)),
              ],
            ),
          ),
          // Swipeable stat pane — shares the outer vertical scroll, so its
          // rows always align with the frozen pane's.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                children: [
                  Row(children: [for (final c in visible) _statHeader(context, c)]),
                  SizedBox(
                      width: statWidth,
                      child: const Divider(height: 1, thickness: 1)),
                  for (final p in rows)
                    Builder(builder: (context) => _statRow(context, p, visible)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Match-page tab for a team name: the TabBar gives each of the three tabs
/// an equal share of the full width (owner feedback — no center-clustered
/// scrollable strip), and long team names scale down to one fitting line
/// rather than wrapping or truncating.
Tab teamNameTab(String name) => Tab(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(name, maxLines: 1),
      ),
    );
