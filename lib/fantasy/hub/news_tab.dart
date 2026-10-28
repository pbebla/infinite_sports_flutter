// The hub's News tab (P3d upgrade of the placeholder, spec §13): a simple
// card feed over `Fantasy/<sport>/<season>/News/Published` — newest first,
// photo when the post carries one (never gating the text), friendly empty
// state until the owner publishes. The composer/AI pipeline is P4/P5.
//
// House rules: streams only; single fade reveal (skeleton until the first
// emit); theme-safe via colorScheme; text wraps; glass-navbar clearance;
// photo fade 200ms, zero under reduced motion.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:intl/intl.dart';

class FantasyNewsTab extends StatefulWidget {
  const FantasyNewsTab({
    super.key,
    required this.sport,
    required this.season,
    this.newsStates,
  });

  final String sport;
  final String season;

  /// Test seam — null = the real FantasyService stream.
  final Stream<List<FantasyNewsPost>>? newsStates;

  @override
  State<FantasyNewsTab> createState() => _FantasyNewsTabState();
}

class _FantasyNewsTabState extends State<FantasyNewsTab> {
  /// null until the first emit (skeleton); empty = friendly empty state.
  List<FantasyNewsPost>? _posts;

  StreamSubscription<List<FantasyNewsPost>>? _newsSub;

  @override
  void initState() {
    super.initState();
    _newsSub = (widget.newsStates ??
            FantasyService.watchNews(widget.sport, widget.season))
        .listen((posts) {
      if (mounted) setState(() => _posts = posts);
    });
  }

  @override
  void dispose() {
    _newsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    final Widget body;
    if (posts == null) {
      body = const _NewsSkeleton(key: ValueKey('news_skeleton'));
    } else if (posts.isEmpty) {
      body = const _NewsEmpty(key: ValueKey('news_empty'));
    } else {
      body = ListView.builder(
        key: const ValueKey('news_feed'),
        padding: EdgeInsets.fromLTRB(
            12, 10, 12, 24 + MediaQuery.paddingOf(context).bottom),
        itemCount: posts.length,
        itemBuilder: (context, i) => _NewsCard(post: posts[i]),
      );
    }
    // Single fade reveal once the stream has emitted.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: body,
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.post});

  final FantasyNewsPost post;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final when = post.atMs <= 0
        ? null
        : DateFormat('MMM d · h:mm a')
            .format(DateTime.fromMillisecondsSinceEpoch(post.atMs));
    return Container(
      key: ValueKey('news_card_${post.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo when the post carries one — it never gates the text (no
          // placeholder box; a failed load collapses away entirely).
          if (post.photoUrl != null)
            CachedNetworkImage(
              imageUrl: post.photoUrl!,
              width: double.infinity,
              height: 160,
              fit: BoxFit.cover,
              fadeInDuration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              placeholderFadeInDuration: Duration.zero,
              placeholder: (_, __) => const SizedBox(height: 160),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.title,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    color: scheme.onSurface,
                  ),
                ),
                if (post.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    post.body,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (when != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    when,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
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

class _NewsEmpty extends StatelessWidget {
  const _NewsEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 48, 24, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.newspaper,
                size: 34, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            'League news lands here during the season.',
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

class _NewsSkeleton extends StatelessWidget {
  const _NewsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          children: const [
            SkeletonBox(width: double.infinity, height: 150, radius: 16),
            SizedBox(height: 12),
            SkeletonBox(width: double.infinity, height: 110, radius: 16),
            SizedBox(height: 12),
            SkeletonLines(count: 3),
          ],
        ),
      ),
    );
  }
}
