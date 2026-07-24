import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/tournamentdetail.dart';
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

  Color _sportColor(String sport) {
    switch (sport.toLowerCase()) {
      case 'soccer':
        return Colors.blue;
      case 'basketball':
        return Colors.orange;
      case 'flag football':
        return Colors.green;
      case 'volleyball':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'registration open':
        return Colors.teal;
      case 'group stage':
        return Colors.blue;
      case 'quarterfinals':
        return Colors.indigo;
      case 'semifinals':
        return Colors.deepPurple;
      case 'final':
        return Colors.red;
      case 'completed':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

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
                        _chip(t.sport, _sportColor(t.sport)),
                        const SizedBox(width: 6),
                        if (t.edition.isNotEmpty)
                          Text(
                            t.edition,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _chip(t.status, _statusColor(t.status)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Image.asset('assets/infinitelarge_dark.png', height: 30),
      ),
      body: Builder(
        builder: (context) {
          final tournaments = _tournaments;
          if (tournaments == null) {
            return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
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

