import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/tournamentdetail.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

class TournamentsPage extends StatefulWidget {
  const TournamentsPage({super.key});

  @override
  State<TournamentsPage> createState() => _TournamentsPageState();
}

class _TournamentsPageState extends State<TournamentsPage> {
  // null = the first snapshot hasn't arrived yet (spinner); live thereafter —
  // a newly created tournament appears here without restarting the app.
  List<Tournament>? _tournaments;
  StreamSubscription<List<Tournament>>? _tournamentsSub;

  @override
  void initState() {
    super.initState();
    _tournamentsSub =
        TournamentService.watchAllTournaments().listen((tournaments) {
      if (mounted) setState(() => _tournaments = tournaments);
    });
  }

  @override
  void dispose() {
    _tournamentsSub?.cancel();
    super.dispose();
  }

  // F3 Fix 3 (chip redesign): the owner disliked the rainbow of per-sport and
  // per-stage colors these two used to hand back — every sport got its own
  // hue (blue soccer, orange basketball, ...) and every stage got its own
  // hue (blue group stage, indigo QF, deep purple SF, red final). New system:
  // sport chip is always neutral, stage/progress chip is always the brand
  // accent, and only "Registration Open" keeps its own (green) color as the
  // universal "open" signal. See _sportChip / _stageChip below.

  bool _isRegistrationOpen(String status) =>
      status.toLowerCase() == 'registration open';

  Widget _buildTournamentCard(BuildContext context, Tournament t) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TournamentDetailPage(
                tournamentId: t.id,
                tournamentName: t.name,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Logo
              TeamLogo(
                url: t.logoUrl,
                size: 52,
                fallbackIcon: Icons.emoji_events,
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _sportChip(context, t.sport),
                        const SizedBox(width: 6),
                        if (t.edition.isNotEmpty)
                          Text(
                            t.edition,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _stageChip(context, t.status),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Sport chip (F3 Fix 3): NEUTRAL in both modes — a flat
  /// surfaceContainerHighest pill with onSurfaceVariant text, no per-sport
  /// color. Solid fill (not alpha-blended like [_chip]) since surfaceVariant
  /// is already a soft neutral tone in both light and dark schemes.
  Widget _sportChip(BuildContext context, String sport) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        sport,
        style: TextStyle(
          fontSize: 11,
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Stage/progress chip (F3 Fix 3): Group Stage / Quarterfinals /
  /// Semifinals / Final / Finished all render in the brand accent (red in
  /// light mode, gold in dark — see [brandAccent]). "Registration Open" is
  /// the one exception, kept green as the universal "open" signal.
  Widget _stageChip(BuildContext context, String status) {
    if (_isRegistrationOpen(status)) {
      return _chip(status, Colors.green);
    }
    return _chip(status, brandAccent(context));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Image.asset('assets/infinite_mark.png', height: 32),
      ),
      body: Builder(
        builder: (context) {
          final tournaments = _tournaments;
          if (tournaments == null) {
            // Skeleton sweep (F3 Fix 2): matches the tournament card list
            // this resolves into below.
            return const SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: SkeletonMatchList(count: 6),
              ),
            );
          }
          if (tournaments.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emoji_events_outlined,
                      size: 64, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'No tournaments available',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                  ),
                ],
              ),
            );
          }

          final all = tournaments;
          final current = all.where((t) => !t.finished).toList();
          final past = all.where((t) => t.finished).toList();

          return ListView(
            padding: EdgeInsets.only(top: 8, bottom: 16 + MediaQuery.paddingOf(context).bottom),
            children: [
              if (current.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Current',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 1.2,
                        ),
                  ),
                ),
                ...current.map((t) => _buildTournamentCard(context, t)),
              ],
              if (past.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Past Tournaments',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                  ),
                ),
                ...past.map((t) => _buildTournamentCard(context, t)),
              ],
            ],
          );
        },
      ),
    );
  }
}

