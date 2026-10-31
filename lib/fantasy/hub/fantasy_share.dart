// Infinite Fantasy share images (owner: "a share button on Team of the week
// and on your own rank — it makes a branded image people can post to
// Instagram stories or group chats").
//
// Two story graphics, both 9:16 — [kStoryWidth] x [kStoryHeight] logical,
// captured at [kStoryPixelRatio] = 1080x1920 (Instagram story size):
//   * [TeamOfWeekStoryCard] — the Dream Team on the SAME neon pitch + chips
//     the in-app card uses (FantasyCourtView, read-only, no prices).
//   * [RankStoryCard] — your team name (real name under it), "#10 of 21",
//     total points, this week's movement and the small season rank line
//     (the panel's own RankHistoryChart).
// Both sit in [FantasyStoryFrame]: logo, title/season line, and the shared
// "Follow Infinite Sports" footer every share card carries.
//
// The images are ALWAYS the dark brand style — they are posted outside the
// app, so they never follow the viewer's theme: the frame swaps in the app's
// own dark theme (theme_provider.darkMode) and every color comes from that
// scheme / the fantasy helpers, exactly as the app renders in dark mode. Text
// scaling and animations are pinned off so the art is identical everywhere.
//
// Plumbing is share_card_service.dart (capture, temp file, iPad-anchored
// system sheet); photos are precached briefly and never gate the share
// (initials fallback).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_rows.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/rank_history_chart.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/misc/share_card_service.dart';
import 'package:infinite_sports_flutter/misc/theme_provider.dart';
import 'package:infinite_sports_flutter/widgets/share_card_footer.dart';

/// The story canvas: 9:16, 1080x1920 once captured at [kStoryPixelRatio].
const double kStoryWidth = 360;
const double kStoryHeight = 640;
const double kStoryPixelRatio = 3;

/// "Futsal Season 15" — the season line on both images and captions.
String fantasySeasonLabel(String sport, String season) =>
    '$sport Season $season';

/// "Infinite Fantasy · Team of the Week · GW8 (Futsal Season 15)".
String teamOfWeekShareCaption(int week, String seasonLabel) =>
    'Infinite Fantasy · Team of the Week · GW$week ($seasonLabel)';

/// "Infinite Fantasy · My rank · #10 of 21 · 512 pts (Futsal Season 15)".
String myRankShareCaption({
  required int rank,
  required int managerCount,
  required int points,
  required String seasonLabel,
}) =>
    'Infinite Fantasy · My rank · #$rank of $managerCount · $points pts '
    '($seasonLabel)';

/// The app's dark theme, keeping the host's font family + fallbacks (so a
/// story renders in the same typeface as the app — and tests can supply real
/// fonts).
ThemeData fantasyStoryTheme(BuildContext context) {
  final body = Theme.of(context).textTheme.bodyMedium;
  final family = body?.fontFamily;
  final fallback = body?.fontFamilyFallback;
  if (family == null && fallback == null) return darkMode;
  return darkMode.copyWith(
    textTheme: darkMode.textTheme
        .apply(fontFamily: family, fontFamilyFallback: fallback),
  );
}

/// The branded story canvas: dark brand gradient with a soft gold glow, the
/// Infinite Fantasy logo, an optional [title] and the [subtitle] line, the
/// [child] filling the middle, the shared footer at the bottom.
class FantasyStoryFrame extends StatelessWidget {
  const FantasyStoryFrame({
    super.key,
    this.title,
    required this.subtitle,
    required this.child,
  });

  final String? title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media =
        (MediaQuery.maybeOf(context) ?? const MediaQueryData()).copyWith(
      textScaler: TextScaler.noScaling,
      disableAnimations: true,
      padding: EdgeInsets.zero,
      viewPadding: EdgeInsets.zero,
      viewInsets: EdgeInsets.zero,
    );
    return MediaQuery(
      data: media,
      child: Theme(
        data: fantasyStoryTheme(context),
        // Material re-roots DefaultTextStyle on the DARK theme's body text.
        child: Material(
          type: MaterialType.transparency,
          child: Builder(builder: _canvas),
        ),
      ),
    );
  }

  Widget _canvas(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final title = this.title;
    return SizedBox(
      width: kStoryWidth,
      height: kStoryHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              FantasyBanner.gradientTop,
              FantasyBanner.gradientBottom,
              FantasyBanner.gradientTop,
            ],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.8),
              radius: 0.9,
              colors: [
                accent.withValues(alpha: 0.16),
                accent.withValues(alpha: 0),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 26),
              Center(
                child: Image.asset(
                  kFantasyLogoAsset,
                  key: const ValueKey('story_logo'),
                  height: 62,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    if (title != null) ...[
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 25,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      subtitle,
                      key: const ValueKey('story_subtitle'),
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: child,
                ),
              ),
              const ShareCardFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Team of the Week story: the five dream players on the neon pitch with
/// name, position and week points — the in-app card's court and chips.
class TeamOfWeekStoryCard extends StatelessWidget {
  const TeamOfWeekStoryCard({
    super.key,
    required this.week,
    required this.seasonLabel,
    required this.team,
    required this.config,
    this.photoUrlFor,
  });

  final int week;
  final String seasonLabel;
  final FantasyDreamTeam team;
  final FantasyConfig config;

  /// Market photo per player name (initials fallback).
  final String? Function(String name)? photoUrlFor;

  @override
  Widget build(BuildContext context) {
    final court = dreamTeamCourt(config, team);
    return FantasyStoryFrame(
      title: 'Team of the Week',
      subtitle: 'GW$week · $seasonLabel',
      child: Center(
        // As big as the middle allows; the court keeps its own aspect.
        child: AspectRatio(
          aspectRatio: useNeonPitchAsset ? pitchAssetAspect : 0.78,
          child: Builder(builder: (context) {
            final theme = Theme.of(context);
            // The pitch artwork is transparent outside its gold rim: let the
            // story's own backdrop show there instead of a card surface.
            return Theme(
              data: theme.copyWith(
                colorScheme: theme.colorScheme
                    .copyWith(surfaceContainerLow: Colors.transparent),
              ),
              child: FantasyCourtView(
                config: config,
                slots: court.slots,
                slotPicks: court.slotPicks,
                onSlotTap: null,
                showPrices: false,
                chipWidth: 84,
                chipAvatarSize: 48,
                weekPointsFor: (name) {
                  final points = court.pointsByName[name];
                  return points == null ? null : '$points pts';
                },
                photoUrlFor: photoUrlFor,
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// The "my rank" story: your team name (real name under it), "#10 of 21"
/// overall, total points, this week's movement and the season rank line.
class RankStoryCard extends StatelessWidget {
  const RankStoryCard({
    super.key,
    required this.row,
    required this.managerCount,
    required this.series,
    required this.seasonLabel,
  });

  /// The signed-in manager's Overall row.
  final LeaderboardRowData row;

  /// Managers on the Overall board (the "of 21").
  final int managerCount;
  final List<RankPoint> series;
  final String seasonLabel;

  /// The headline is the TEAM name with the real name under it (the rows
  /// put the real name first); either alone when the other is unknown, and
  /// never the same name twice.
  static ({String primary, String? secondary}) headline(
      LeaderboardRowData row) {
    final team = row.teamName;
    if (team == null) return (primary: row.name, secondary: null);
    final real = row.realName;
    final same =
        real != null && real.trim().toLowerCase() == team.trim().toLowerCase();
    return (primary: team, secondary: same ? null : real);
  }

  @override
  Widget build(BuildContext context) {
    return FantasyStoryFrame(
      subtitle: seasonLabel,
      child: Builder(builder: _content),
    );
  }

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final names = headline(row);
    final secondary = names.secondary;
    final journey = rankJourneyLabel(series);
    final muted = scheme.onSurfaceVariant;

    // Very long names scale the whole block down instead of overflowing the
    // fixed canvas (they still wrap — never ellipsized).
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: kStoryWidth - 32,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 14),
            Text(
              names.primary,
              key: const ValueKey('rank_story_team'),
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(
                fontSize: 26,
                height: 1.15,
                fontWeight: FontWeight.w900,
                color: scheme.onSurface,
              ),
            ),
            if (secondary != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  secondary,
                  key: const ValueKey('rank_story_real_name'),
                  textAlign: TextAlign.center,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '#${row.displayRank}',
                    key: const ValueKey('rank_story_rank'),
                    style: TextStyle(
                      fontSize: 84,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'of $managerCount',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'OVERALL RANK',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: muted,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _StoryStat(
                    label: 'Total points',
                    value: '${row.points}',
                    unit: 'pts',
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StoryStat(
                    label: 'This week',
                    value: movementLabel(row.movement),
                    color:
                        movementColor(context, movementDirection(row.movement)),
                  ),
                ),
              ],
            ),
            if (journey != null) ...[
              const SizedBox(height: 12),
              _StoryPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Rank this season',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: muted,
                            ),
                          ),
                        ),
                        Text(
                          journey,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    RankHistoryChart(series: series),
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

/// A rounded tile on the story backdrop.
class _StoryPanel extends StatelessWidget {
  const _StoryPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

/// One big-number tile: a muted label over the value (+ an optional unit).
class _StoryStat extends StatelessWidget {
  const _StoryStat({
    required this.label,
    required this.value,
    required this.color,
    this.unit,
  });

  final String label;
  final String value;
  final Color color;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final unit = this.unit;
    return _StoryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: muted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The images every story needs decoded before capture.
const List<AssetImage> kStoryAssets = [
  AssetImage(kFantasyLogoAsset),
  AssetImage(kNeonPitchAsset),
  AssetImage('assets/infinite_mark.png'),
];

/// Renders [story] at 1080x1920 and opens the share sheet with [caption],
/// anchored to [context]'s widget (pass the tapped button's context).
/// [photoUrls] are precached briefly (never gating). [share] replaces the
/// system sheet (tests). Never throws.
Future<void> shareFantasyStory(
  BuildContext context,
  Widget story, {
  required String caption,
  Iterable<String?> photoUrls = const [],
  SharePng? share,
}) =>
    shareCardImage(
      context,
      story,
      caption: caption,
      filePrefix: 'infinite_fantasy',
      pixelRatio: kStoryPixelRatio,
      precache: [
        ...kStoryAssets,
        for (final url in photoUrls)
          if (url != null && url.isNotEmpty) CachedNetworkImageProvider(url),
      ],
      share: share,
    );

/// Shares the Team of the Week for [week] as a story image.
Future<void> shareTeamOfWeekStory(
  BuildContext context, {
  required int week,
  required String seasonLabel,
  required FantasyDreamTeam team,
  required FantasyConfig config,
  String? Function(String name)? photoUrlFor,
  SharePng? share,
}) =>
    shareFantasyStory(
      context,
      TeamOfWeekStoryCard(
        week: week,
        seasonLabel: seasonLabel,
        team: team,
        config: config,
        photoUrlFor: photoUrlFor,
      ),
      caption: teamOfWeekShareCaption(week, seasonLabel),
      photoUrls: [for (final p in team.players) photoUrlFor?.call(p.name)],
      share: share,
    );

/// Shares the signed-in manager's season rank as a story image.
Future<void> shareMyRankStory(
  BuildContext context, {
  required LeaderboardRowData row,
  required int managerCount,
  required List<RankPoint> series,
  required String seasonLabel,
  SharePng? share,
}) =>
    shareFantasyStory(
      context,
      RankStoryCard(
        row: row,
        managerCount: managerCount,
        series: series,
        seasonLabel: seasonLabel,
      ),
      caption: myRankShareCaption(
        rank: row.displayRank,
        managerCount: managerCount,
        points: row.points,
        seasonLabel: seasonLabel,
      ),
      share: share,
    );
