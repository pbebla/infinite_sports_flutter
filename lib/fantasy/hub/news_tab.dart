// The hub's News tab (P3d upgrade of the placeholder, spec §13): a simple
// card feed over `Fantasy/<sport>/<season>/News/Published` — newest first,
// photo when the post carries one (never gating the text), friendly empty
// state until the owner publishes.
//
// News desk 2.0 (spec 2026-10-28 §4.2): each card opens with a header line
// ("Spotlight · GW7"), tagged players render under the body
// (news_player_card.dart — View player calls the hub's [onOpenPlayer]), and
// a push tap can FOCUS a post: once it is in the feed the list scrolls to it
// and outlines it for 1.2s; a post that never shows up within
// [FantasyNewsTab.focusGrace] after the first emit (deleted after its push
// went out) gets one "This post was removed." SnackBar.
//
// House rules: streams only; single fade reveal (skeleton until the first
// emit); theme-safe via colorScheme; text wraps; glass-navbar clearance;
// photo fade 200ms, zero under reduced motion (the focus scroll and
// highlight are instant under reduced motion too).

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/hub/news_player_card.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:intl/intl.dart';

class FantasyNewsTab extends StatefulWidget {
  const FantasyNewsTab({
    super.key,
    required this.sport,
    required this.season,
    this.newsStates,
    this.focusPostId,
    this.onFocusHandled,
    this.onOpenPlayer,
  });

  final String sport;
  final String season;

  /// Test seam — null = the real FantasyService stream.
  final Stream<List<FantasyNewsPost>>? newsStates;

  /// A post to scroll to and highlight (a tapped news push), or null.
  final String? focusPostId;

  /// Called once the focus has been resolved (shown, or reported removed)
  /// so the hub can drop it — a remounted tab must not re-focus.
  final VoidCallback? onFocusHandled;

  /// "View player" on a tagged-player card → the hub opens the market
  /// player sheet. null hides the button (and row taps).
  final void Function(String name)? onOpenPlayer;

  /// How long after the FIRST emit a focused post may take to appear before
  /// the tab says it was removed. The first emit can be stale (the session
  /// snapshot cache, or RTDB's on-disk persistence) while the live snapshot
  /// with a just-published post is still on its way.
  static const Duration focusGrace = Duration(seconds: 3);

  /// How long the focused post keeps its outline once scrolled into view.
  static const Duration highlightFor = Duration(milliseconds: 1200);

  @override
  State<FantasyNewsTab> createState() => _FantasyNewsTabState();
}

class _FantasyNewsTabState extends State<FantasyNewsTab> {
  /// null until the first emit (skeleton); empty = friendly empty state.
  List<FantasyNewsPost>? _posts;

  StreamSubscription<List<FantasyNewsPost>>? _newsSub;

  final ScrollController _scroll = ScrollController();

  /// Attached to the focused post's card only — its context drives the
  /// reveal scroll.
  final GlobalKey _focusKey = GlobalKey(debugLabel: 'news_focus');

  /// Focus resolved (found, or reported removed) — never again this mount.
  bool _focusDone = false;

  /// The focused post once found. Kept for the whole mount (even after the
  /// hub clears focusPostId) so the card's subtree never re-parents — that
  /// would rebuild it and skip the highlight's fade-out.
  String? _focusTargetId;
  Timer? _graceTimer;
  Timer? _highlightTimer;

  /// The post currently outlined (the focused one, for [highlightFor]).
  String? _highlightId;

  @override
  void initState() {
    super.initState();
    _newsSub = (widget.newsStates ??
            FantasyService.watchNews(widget.sport, widget.season))
        .listen((posts) {
      if (!mounted) return;
      final first = _posts == null;
      setState(() => _posts = posts);
      _resolveFocus(posts, firstEmit: first);
    });
  }

  @override
  void dispose() {
    _newsSub?.cancel();
    _graceTimer?.cancel();
    _highlightTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // ── Push-tap focus ────────────────────────────────────────────────────

  void _resolveFocus(List<FantasyNewsPost> posts, {required bool firstEmit}) {
    final id = widget.focusPostId;
    if (id == null || _focusDone) return;
    if (posts.any((p) => p.id == id)) {
      _focusDone = true;
      _graceTimer?.cancel();
      setState(() {
        _focusTargetId = id;
        _highlightId = id;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealFocused());
      widget.onFocusHandled?.call();
    } else if (firstEmit) {
      _graceTimer = Timer(FantasyNewsTab.focusGrace, _reportRemoved);
    }
  }

  void _reportRemoved() {
    if (!mounted || _focusDone) return;
    _focusDone = true;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
          const SnackBar(content: Text('This post was removed.')));
    widget.onFocusHandled?.call();
  }

  /// Scrolls THIS list (never the hub's TabBarView — Scrollable.ensureVisible
  /// would also nudge the horizontal tab pager by the card's side margin) so
  /// the focused card sits at the top. The list is lazy: while the card
  /// isn't built yet, step down a screen per frame until it is (pushes are
  /// about new posts, so this is almost always the first card).
  Future<void> _revealFocused() async {
    if (!mounted) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    for (var step = 0; step < 80 && mounted; step++) {
      if (!_scroll.hasClients) {
        await WidgetsBinding.instance.endOfFrame;
        continue;
      }
      final position = _scroll.position;
      final object = _focusKey.currentContext?.findRenderObject();
      if (object != null && object.attached) {
        final viewport = RenderAbstractViewport.maybeOf(object);
        if (viewport != null) {
          // Keep the list's top padding as breathing room above the card.
          final target = (viewport.getOffsetToReveal(object, 0.0).offset - 10)
              .clamp(position.minScrollExtent, position.maxScrollExtent);
          if (reduceMotion) {
            _scroll.jumpTo(target);
          } else {
            await _scroll.animateTo(
              target,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
            );
          }
        }
        break;
      }
      if (position.pixels >= position.maxScrollExtent) break;
      _scroll.jumpTo(math.min(position.pixels + position.viewportDimension * 0.9,
          position.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    _highlightTimer?.cancel();
    _highlightTimer = Timer(FantasyNewsTab.highlightFor, () {
      if (mounted) setState(() => _highlightId = null);
    });
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
      final focusId = _focusTargetId ?? widget.focusPostId;
      body = ListView.builder(
        key: const ValueKey('news_feed'),
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
            12, 10, 12, 24 + MediaQuery.paddingOf(context).bottom),
        itemCount: posts.length,
        itemBuilder: (context, i) {
          final post = posts[i];
          final card = _NewsCard(
            post: post,
            highlighted: post.id == _highlightId,
            onOpenPlayer: widget.onOpenPlayer,
          );
          return post.id == focusId
              ? KeyedSubtree(key: _focusKey, child: card)
              : card;
        },
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
  const _NewsCard({
    required this.post,
    required this.highlighted,
    this.onOpenPlayer,
  });

  final FantasyNewsPost post;

  /// The push-tapped post's brief outline.
  final bool highlighted;
  final void Function(String name)? onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final when = post.atMs <= 0
        ? null
        : DateFormat('MMM d · h:mm a')
            .format(DateTime.fromMillisecondsSinceEpoch(post.atMs));
    return AnimatedContainer(
      key: ValueKey('news_card_${post.id}'),
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      // The highlight rides on the FOREGROUND decoration so it never shifts
      // the card's layout.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? scheme.primary : scheme.primary.withValues(alpha: 0),
          width: 2,
        ),
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  post.headerText,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
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
                if (post.players.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  NewsPostPlayers(
                    players: post.players,
                    onOpenPlayer: onOpenPlayer,
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
