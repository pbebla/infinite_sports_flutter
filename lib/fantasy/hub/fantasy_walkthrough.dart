// First-open walkthrough (P3a Task 4, spec §10a): a short swipeable intro —
// build your 7 → captain ×2 → deadline → points from real games — skippable,
// shown once (FantasyPrefs flag owned by the caller). Copy renders from the
// live config where it carries numbers, so the intro can't contradict the
// Rules page.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';

class FantasyWalkthrough extends StatefulWidget {
  const FantasyWalkthrough({
    super.key,
    required this.config,
    required this.onDone,
  });

  final FantasyConfig config;

  /// Called on Skip and on the final card's button — the caller marks the
  /// prefs flag and reveals the hub.
  final VoidCallback onDone;

  @override
  State<FantasyWalkthrough> createState() => _FantasyWalkthroughState();
}

class _FantasyWalkthroughState extends State<FantasyWalkthrough> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_WalkthroughCard> get _cards {
    final cfg = widget.config;
    return [
      _WalkthroughCard(
        image: 'assets/fantasy/fantasy_logo_regal.png',
        title: 'Build your seven',
        body: "Pick ${cfg.squadSize} of the league's real players within a "
            '${formatMoneyTenths(cfg.budgetTenths)} budget — '
            '${FantasyPosition.gk.count(cfg.startersGk)}, '
            '${FantasyPosition.def.count(cfg.startersDef)} and '
            '${FantasyPosition.att.count(cfg.startersAtt)} start, plus a '
            '${cfg.benchDef + cfg.benchAtt}-player bench.',
      ),
      _WalkthroughCard(
        icon: Icons.military_tech,
        title: 'Captain for double',
        body: 'Make one starter your captain: every point they score counts '
            '×${cfg.captainMultiplier}. If the captain misses the game, '
            'your vice-captain scores the double instead.',
      ),
      _WalkthroughCard(
        icon: Icons.timer_outlined,
        title: 'Beat the deadline',
        body: 'Your squad locks at ${formatLockHour(cfg.lockHour)} league '
            'time on game day and reopens for changes the next day. Make '
            'your moves before the whistle.',
      ),
      const _WalkthroughCard(
        icon: Icons.sports_soccer,
        title: 'Real games, real points',
        body: 'Goals, assists, saves and clean sheets in real league games '
            'become your fantasy points, live as they happen. The Rules tab '
            'has every number whenever you need it.',
      ),
    ];
  }

  void _next(int cardCount) {
    if (_page >= cardCount - 1) {
      widget.onDone();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    final last = _page == cards.length - 1;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [FantasyBanner.gradientTop, FantasyBanner.gradientBottom],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: TextButton(
                  onPressed: widget.onDone,
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: cards.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => cards[i],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < cards.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? TournamentColors.gold
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 18, 24, 18 + MediaQuery.paddingOf(context).bottom),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _next(cards.length),
                  style: FilledButton.styleFrom(
                    backgroundColor: TournamentColors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  child: Text(last ? "Let's play" : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalkthroughCard extends StatelessWidget {
  const _WalkthroughCard({
    this.image,
    this.icon,
    required this.title,
    required this.body,
  });

  final String? image;
  final IconData? icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (image != null)
            Image.asset(image!, height: 110, fit: BoxFit.contain)
          else
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 46, color: TournamentColors.gold),
            ),
          const SizedBox(height: 28),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
