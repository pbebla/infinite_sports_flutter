import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/trophy_icons.dart';
import 'package:infinite_sports_flutter/model/award.dart';

// ─── Shared constants ─────────────────────────────────────────────────────────

const double _kWidth = 360;
const double _kHeight = 450;
const Color _kPrimary = Color(0xFFD00000);
const Color _kFooter = Color(0xFF111111);

// ─── Shared scaffold ──────────────────────────────────────────────────────────

/// Gradient header with player photo + name + subtitle; Infinite Sports logo
/// footer. The [body] fills the space between header and footer.
class _ProfileCardScaffold extends StatelessWidget {
  final String name;
  final String photoUrl;
  final String subtitle; // e.g. "Eagles · Futsal"
  final Widget body;

  const _ProfileCardScaffold({
    required this.name,
    required this.photoUrl,
    required this.subtitle,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kWidth,
      height: _kHeight,
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8B0000), Color(0xFFD00000)],
              ),
            ),
            child: Row(
              children: [
                _Avatar(url: photoUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Small IS logo in header (white tinted)
                Image.asset(
                  'assets/infinite_mark.png',
                  height: 28,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ],
            ),
          ),
          // ── Body ─────────────────────────────────────────────────────────
          Expanded(child: body),
          // ── Footer ───────────────────────────────────────────────────────
          Container(
            color: _kFooter,
            padding:
                const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/infinite_mark.png', height: 34),
                const SizedBox(width: 6),
                const Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Follow '),
                        TextSpan(
                          text: 'Infinite Sports',
                          style: TextStyle(color: Color(0xFFFF5A5A)),
                        ),
                        TextSpan(text: ' for live scores'),
                      ],
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String url;

  const _Avatar({required this.url});

  @override
  Widget build(BuildContext context) {
    const double size = 56;
    final fallback = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white24,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 32),
    );
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

// ─── Card 1: Trophy Cabinet ───────────────────────────────────────────────────

/// Fixed-size card (360×450 logical) for sharing a player's trophy cabinet.
class ShareProfileCabinetCard extends StatelessWidget {
  final String name;
  final String photoUrl;

  /// e.g. "Eagles · Futsal"
  final String currentLabel;
  final List<Award> awards;

  static const double kWidth = _kWidth;
  static const double kHeight = _kHeight;

  const ShareProfileCabinetCard({
    super.key,
    required this.name,
    required this.photoUrl,
    required this.currentLabel,
    required this.awards,
  });

  @override
  Widget build(BuildContext context) {
    final shown = awards.take(8).toList();
    final extra = awards.length - shown.length;

    return _ProfileCardScaffold(
      name: name,
      photoUrl: photoUrl,
      subtitle: currentLabel,
      body: Container(
        color: const Color(0xFFFAFAFA),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Headline
            Row(
              children: [
                const Icon(Icons.emoji_events,
                    color: _kPrimary, size: 20),
                const SizedBox(width: 6),
                Text(
                  '${awards.length} ${awards.length == 1 ? 'Trophy' : 'Trophies'}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (shown.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No trophies yet',
                    style: TextStyle(color: Color(0xFF999999), fontSize: 13),
                  ),
                ),
              )
            else ...[
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in shown) _MiniTrophy(award: a),
                    if (extra > 0) _MoreChip(extra: extra),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniTrophy extends StatelessWidget {
  final Award award;

  const _MiniTrophy({required this.award});

  @override
  Widget build(BuildContext context) {
    final color = tierColor(award.tier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        isAssetIcon(award.icon)
            ? trophyIconWidget(award.icon, size: 44)
            : CircleAvatar(
                radius: 22,
                backgroundColor: color,
                child: Icon(
                  trophyIconData(award.icon),
                  color: Colors.white,
                  size: 20,
                ),
              ),
        const SizedBox(height: 4),
        SizedBox(
          width: 56,
          child: Text(
            award.name,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF333333),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MoreChip extends StatelessWidget {
  final int extra;

  const _MoreChip({required this.extra});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: _kPrimary.withValues(alpha: 0.15),
          child: Text(
            '+$extra',
            style: const TextStyle(
              color: _kPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const SizedBox(
          width: 56,
          child: Text(
            'more',
            style: TextStyle(
              fontSize: 9,
              color: Color(0xFF666666),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ─── Card 2: Stats ────────────────────────────────────────────────────────────

/// Fixed-size card for sharing per-competition stats.
class ShareProfileStatsCard extends StatelessWidget {
  final String name;
  final String photoUrl;

  /// e.g. "Futsal · Season 15"
  final String competitionLabel;

  /// Pre-ordered, up to 5 entries (label + value pairs).
  final List<({String label, String value})> stats;

  static const double kWidth = _kWidth;
  static const double kHeight = _kHeight;

  const ShareProfileStatsCard({
    super.key,
    required this.name,
    required this.photoUrl,
    required this.competitionLabel,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return _ProfileCardScaffold(
      name: name,
      photoUrl: photoUrl,
      subtitle: competitionLabel,
      body: Container(
        color: const Color(0xFFFAFAFA),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Row(
              children: [
                const Icon(Icons.bar_chart, color: _kPrimary, size: 20),
                const SizedBox(width: 6),
                const Text(
                  'Stats',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              competitionLabel,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF777777),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFE0E0E0)),
            const SizedBox(height: 8),
            if (stats.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No stats recorded',
                    style: TextStyle(color: Color(0xFF999999), fontSize: 13),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final s in stats.take(5)) _StatLine(stat: s),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  final ({String label, String value}) stat;

  const _StatLine({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stat.label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF444444),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            stat.value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Card 3: Career ───────────────────────────────────────────────────────────

/// Fixed-size card for sharing career headline totals.
class ShareProfileCareerCard extends StatelessWidget {
  final String name;
  final String photoUrl;

  /// e.g. [('Sports Played', '3'), ('Games', '47'), ('Goals', '22'), ('Trophies', '5')]
  final List<({String label, String value})> headlineTotals;

  static const double kWidth = _kWidth;
  static const double kHeight = _kHeight;

  const ShareProfileCareerCard({
    super.key,
    required this.name,
    required this.photoUrl,
    required this.headlineTotals,
  });

  @override
  Widget build(BuildContext context) {
    return _ProfileCardScaffold(
      name: name,
      photoUrl: photoUrl,
      subtitle: 'Career',
      body: Container(
        color: const Color(0xFFFAFAFA),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timeline, color: _kPrimary, size: 20),
                const SizedBox(width: 6),
                const Text(
                  'Career Totals',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (headlineTotals.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No career data yet',
                    style: TextStyle(color: Color(0xFF999999), fontSize: 13),
                  ),
                ),
              )
            else
              Expanded(
                child: _BigNumberGrid(totals: headlineTotals),
              ),
          ],
        ),
      ),
    );
  }
}

class _BigNumberGrid extends StatelessWidget {
  final List<({String label, String value})> totals;

  const _BigNumberGrid({required this.totals});

  @override
  Widget build(BuildContext context) {
    // Up to 4 big-number cells in a 2×2 grid.
    final cells = totals.take(4).toList();
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: cells
          .map((t) => _BigNumberCell(label: t.label, value: t.value))
          .toList(),
    );
  }
}

class _BigNumberCell extends StatelessWidget {
  final String label;
  final String value;

  const _BigNumberCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _kPrimary,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF777777),
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
