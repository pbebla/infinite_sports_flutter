// The season-pass pay card (paid-access spec 2026-11-01 §6) — what the My
// Team tab shows in pass mode until this fan's `Access/<uid>` is active.
// Every state is LIVE from the hub's Access stream (nothing polls):
//
//   none      headline · body · price, then the owner's CTA (Copy.Button)
//             which opens the enabled methods: card (Stripe Checkout in the
//             phone's browser), Venmo (deep link + "I sent it"), Zelle
//             (instructions + "I sent it");
//   pending   "Got it — Zaya will confirm…" + Change payment method;
//   revoked   "Your access was removed…" + the methods straight away;
//   active    nothing — the hub shows the normal name step / court;
//   degraded  the read FAILED before any value was known: a retry line,
//             never the methods as if unpaid (error ≠ fact).
//
// Payment happens OUTSIDE the app (§2): the card only opens links and
// records claims. The fan app never mentions grants, free access or admins —
// a granted fan simply never sees this card.
//
// House rules: colorScheme + the gold/primary fantasy accent pairing (both
// themes), 360 px (every text wraps), tappable text never underlined, the
// Venmo link + Zelle identity come from payment_links.dart (one source).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_access.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/registration/payment_links.dart';

/// The card's side effects, injected by the hub (FantasyService + url_launcher
/// in production; recorders in tests).
class FantasyAccessActions {
  const FantasyAccessActions({
    required this.createCheckoutUrl,
    required this.launch,
    required this.submitClaim,
    this.retryAccess,
  });

  /// `FantasyService.createCheckoutUrl` — null = already active.
  final Future<Uri?> Function() createCheckoutUrl;

  /// `launchUrl(uri, mode: LaunchMode.externalApplication)`; false = the
  /// phone could not open it.
  final Future<bool> Function(Uri uri) launch;

  /// `FantasyService.submitAccessClaim` ("I sent it").
  final Future<void> Function(
      FantasyAccessMethod method, double amountDollars, String note) submitClaim;

  /// Re-subscribes the Access feed after a failed read (the degraded face's
  /// "Try again"); null = no retry affordance.
  final VoidCallback? retryAccess;
}

/// Fan-facing copy that is not owner-editable (the editable paywall copy is
/// `Config/Access/Copy`, spec §9).
const String kAccessPendingText =
    "Got it — Zaya will confirm your payment shortly; we'll let you know.";
const String kAccessRevokedText =
    'Your access was removed. Pay again to keep playing.';
const String kAccessBrowserText =
    'Finish in your browser — this page updates by itself when Stripe '
    'confirms.';
const String kAccessDegradedText =
    "We couldn't check your access just now.";
const String kAccessCardErrorText =
    "Couldn't start the card payment — try again.";
const String kAccessOpenErrorText =
    "Couldn't open the payment page — try again.";
const String kAccessVenmoErrorText = "Couldn't open Venmo — try again.";
const String kAccessClaimErrorText = "Couldn't send that — try again.";

class AccessPayCard extends StatefulWidget {
  const AccessPayCard({
    super.key,
    required this.sport,
    required this.season,
    required this.config,
    required this.access,
    required this.displayName,
    required this.actions,
  });

  final String sport;
  final String season;

  /// The live `Config/Access` block (mode, price, methods, copy).
  final FantasyAccessConfig config;

  /// The live own `Access/<uid>` state.
  final FantasyAccessState access;

  /// The signed-in user's display name — the Venmo / claim note's tail.
  final String displayName;

  final FantasyAccessActions actions;

  @override
  State<AccessPayCard> createState() => _AccessPayCardState();
}

class _AccessPayCardState extends State<AccessPayCard> {
  /// The methods are open (the CTA, Change payment method, or revoked).
  bool _expanded = false;

  bool _cardBusy = false;

  /// The Checkout link already opened — "Open again" re-launches it.
  Uri? _cardUri;
  String? _cardError;

  /// Venmo opened: the "I sent it" row is showing.
  bool _venmoOpened = false;
  String? _venmoError;

  bool _claimBusy = false;
  String? _claimError;

  /// A claim was written from this card and the stream hasn't shown
  /// pending yet (the server trigger flips it within seconds): show the
  /// pending face at once. Cleared the moment the stream reports anything
  /// other than none — a later none then means the claim was rejected.
  bool _claimedLocally = false;

  @override
  void didUpdateWidget(AccessPayCard old) {
    super.didUpdateWidget(old);
    if (widget.access.status != FantasyAccessStatus.none) {
      _claimedLocally = false;
    }
  }

  String get _note => accessClaimNote(
      sport: widget.sport,
      season: widget.season,
      displayName: widget.displayName);

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _payByCard() async {
    if (_cardBusy) return;
    setState(() {
      _cardBusy = true;
      _cardError = null;
    });
    try {
      final uri = await widget.actions.createCheckoutUrl();
      if (!mounted) return;
      if (uri == null) {
        // Already active — the live stream is about to dismiss this card.
        setState(() => _cardBusy = false);
        return;
      }
      final ok = await widget.actions.launch(uri);
      if (!mounted) return;
      setState(() {
        _cardBusy = false;
        if (ok) {
          _cardUri = uri;
        } else {
          _cardError = kAccessOpenErrorText;
        }
      });
    } catch (e) {
      debugPrint('AccessPayCard: checkout failed: $e');
      if (!mounted) return;
      setState(() {
        _cardBusy = false;
        _cardError = kAccessCardErrorText;
      });
    }
  }

  Future<void> _openAgain() async {
    final uri = _cardUri;
    if (uri == null) return _payByCard();
    final ok = await widget.actions.launch(uri);
    if (!mounted || ok) return;
    setState(() => _cardError = kAccessOpenErrorText);
  }

  Future<void> _payWithVenmo() async {
    final ok = await widget.actions.launch(
        venmoPayUri(amount: widget.config.amountDollars, note: _note));
    if (!mounted) return;
    setState(() {
      _venmoOpened = ok;
      _venmoError = ok ? null : kAccessVenmoErrorText;
    });
  }

  Future<void> _sendClaim(FantasyAccessMethod method) async {
    if (_claimBusy) return;
    setState(() {
      _claimBusy = true;
      _claimError = null;
    });
    try {
      await widget.actions
          .submitClaim(method, widget.config.amountDollars, _note);
      if (!mounted) return;
      setState(() {
        _claimBusy = false;
        _claimedLocally = true;
        _expanded = false;
        _venmoOpened = false;
      });
    } catch (e) {
      debugPrint('AccessPayCard: claim failed: $e');
      if (!mounted) return;
      setState(() {
        _claimBusy = false;
        _claimError = kAccessClaimErrorText;
      });
    }
  }

  void _changeMethod() => setState(() {
        _expanded = true;
        _claimedLocally = false;
      });

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final access = widget.access;
    if (access.isActive) return const SizedBox.shrink();
    if (access.degraded && access.status == FantasyAccessStatus.none) {
      return _Shell(
        key: const ValueKey('access_pay_card'),
        child: _DegradedFace(onRetry: widget.actions.retryAccess),
      );
    }
    final pending =
        access.status == FantasyAccessStatus.pending || _claimedLocally;
    if (pending && !_expanded) {
      return _Shell(
        key: const ValueKey('access_pay_card'),
        child: _PendingFace(onChangeMethod: _changeMethod),
      );
    }
    final revoked = access.status == FantasyAccessStatus.revoked;
    return _Shell(
      key: const ValueKey('access_pay_card'),
      child: _payFace(context, revoked: revoked),
    );
  }

  Widget _payFace(BuildContext context, {required bool revoked}) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final cfg = widget.config;
    final sport = widget.sport;
    final season = widget.season;
    final showMethods = _expanded || revoked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeadIcon(icon: Icons.workspace_premium_rounded, accent: accent),
        const SizedBox(height: 12),
        Text(
          cfg.headlineFor(sport: sport, season: season),
          textAlign: TextAlign.center,
          softWrap: true,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          cfg.bodyFor(sport: sport, season: season),
          textAlign: TextAlign.center,
          softWrap: true,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          key: const ValueKey('access_pay_card_price'),
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(
              cfg.priceLabel,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
            Text(
              'season pass',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (revoked) ...[
          const SizedBox(height: 12),
          _InlineLine(
            key: const ValueKey('access_pay_card_revoked'),
            icon: Icons.error_outline_rounded,
            text: kAccessRevokedText,
            color: fantasyDownRed(context),
          ),
        ],
        const SizedBox(height: 16),
        if (!showMethods)
          _AccentButton(
            key: const ValueKey('access_pay_card_cta'),
            label: cfg.buttonFor(sport: sport, season: season),
            onPressed: () => setState(() => _expanded = true),
          )
        else
          ..._methods(context),
      ],
    );
  }

  List<Widget> _methods(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfg = widget.config;
    final price = cfg.priceLabel;
    final out = <Widget>[];

    if (cfg.card) {
      out.add(_AccentButton(
        key: const ValueKey('access_pay_card_card'),
        icon: Icons.credit_card,
        label: _cardBusy ? 'Opening…' : 'Pay by card',
        busy: _cardBusy,
        onPressed: _cardBusy ? null : _payByCard,
      ));
      if (_cardUri != null && _cardError == null) {
        out.add(const SizedBox(height: 8));
        out.add(_InlineLine(
          key: const ValueKey('access_pay_card_browser'),
          icon: Icons.open_in_browser_rounded,
          text: kAccessBrowserText,
          color: scheme.onSurfaceVariant,
          trailing: TextButton(
            key: const ValueKey('access_pay_card_open_again'),
            onPressed: _openAgain,
            style: TextButton.styleFrom(
              foregroundColor: fantasyAccent(context),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Open again'),
          ),
        ));
      }
      if (_cardError != null) {
        out.add(const SizedBox(height: 8));
        out.add(_InlineLine(
          key: const ValueKey('access_pay_card_error'),
          icon: Icons.error_outline_rounded,
          text: _cardError!,
          color: fantasyDownRed(context),
          trailing: TextButton(
            key: const ValueKey('access_pay_card_retry'),
            onPressed: _cardBusy ? null : _payByCard,
            style: TextButton.styleFrom(
              foregroundColor: fantasyAccent(context),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Retry'),
          ),
        ));
      }
      out.add(const SizedBox(height: 10));
    }

    if (cfg.venmo) {
      out.add(SizedBox(
        height: 48,
        child: ElevatedButton.icon(
          key: const ValueKey('access_pay_card_venmo'),
          style: ElevatedButton.styleFrom(
            backgroundColor: kVenmoBlue,
            foregroundColor: Colors.white,
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Pay with Venmo'),
          onPressed: _payWithVenmo,
        ),
      ));
      if (_venmoError != null) {
        out.add(const SizedBox(height: 8));
        out.add(_InlineLine(
          key: const ValueKey('access_pay_card_venmo_error'),
          icon: Icons.error_outline_rounded,
          text: _venmoError!,
          color: fantasyDownRed(context),
        ));
      }
      if (_venmoOpened) {
        out.add(const SizedBox(height: 8));
        out.add(_SentRow(
          sentKey: const ValueKey('access_pay_card_sent'),
          question: 'Sent $price on Venmo?',
          busy: _claimBusy,
          onSent: () => _sendClaim(FantasyAccessMethod.venmo),
        ));
      }
      out.add(const SizedBox(height: 10));
    }

    if (cfg.zelle) {
      out.add(_ZelleBox(
        price: price,
        busy: _claimBusy,
        onSent: () => _sendClaim(FantasyAccessMethod.zelle),
      ));
      out.add(const SizedBox(height: 10));
    }

    if (_claimError != null) {
      out.add(_InlineLine(
        key: const ValueKey('access_pay_card_claim_error'),
        icon: Icons.error_outline_rounded,
        text: _claimError!,
        color: fantasyDownRed(context),
      ));
      out.add(const SizedBox(height: 10));
    }

    if (out.isNotEmpty) out.removeLast(); // the trailing spacer
    return out;
  }
}

// ── Faces ────────────────────────────────────────────────────────────────

class _PendingFace extends StatelessWidget {
  const _PendingFace({required this.onChangeMethod});

  final VoidCallback onChangeMethod;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    return Column(
      key: const ValueKey('access_pay_card_pending'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeadIcon(icon: Icons.hourglass_top_rounded, accent: accent),
        const SizedBox(height: 12),
        Text(
          'Payment noted',
          textAlign: TextAlign.center,
          softWrap: true,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          kAccessPendingText,
          textAlign: TextAlign.center,
          softWrap: true,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            key: const ValueKey('access_pay_card_change'),
            onPressed: onChangeMethod,
            style: TextButton.styleFrom(foregroundColor: accent),
            child: const Text('Change payment method'),
          ),
        ),
      ],
    );
  }
}

class _DegradedFace extends StatelessWidget {
  const _DegradedFace({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    return Column(
      key: const ValueKey('access_pay_card_degraded'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeadIcon(icon: Icons.cloud_off_rounded, accent: accent),
        const SizedBox(height: 12),
        Text(
          kAccessDegradedText,
          textAlign: TextAlign.center,
          softWrap: true,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.4,
            color: scheme.onSurface,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          Center(
            child: OutlinedButton(
              key: const ValueKey('access_pay_card_retry_access'),
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.7)),
              ),
              child: const Text('Try again'),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Pieces ───────────────────────────────────────────────────────────────

class _Shell extends StatelessWidget {
  const _Shell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _HeadIcon extends StatelessWidget {
  const _HeadIcon({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 30, color: accent),
      ),
    );
  }
}

/// The hub's primary-action look (the Save button's pairing): accent fill,
/// black text in dark, onPrimary in light.
class _AccentButton extends StatelessWidget {
  const _AccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = fantasyAccent(context);
    final fg = isDark ? Colors.black : Theme.of(context).colorScheme.onPrimary;
    final style = FilledButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: fg,
      disabledBackgroundColor: accent.withValues(alpha: 0.5),
      disabledForegroundColor: fg.withValues(alpha: 0.7),
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    );
    final leading = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : (icon == null ? null : Icon(icon));
    if (leading == null) {
      return FilledButton(onPressed: onPressed, style: style, child: Text(label));
    }
    return FilledButton.icon(
        onPressed: onPressed, style: style, icon: leading, label: Text(label));
  }
}

/// "Sent $10 on Venmo?" + I sent it.
class _SentRow extends StatelessWidget {
  const _SentRow({
    required this.sentKey,
    required this.question,
    required this.busy,
    required this.onSent,
  });

  final Key sentKey;
  final String question;
  final bool busy;
  final VoidCallback onSent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            question,
            softWrap: true,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _AccentButton(
          key: sentKey,
          label: busy ? 'Sending…' : 'I sent it',
          busy: busy,
          onPressed: busy ? null : onSent,
        ),
      ],
    );
  }
}

/// The Zelle instructions (number + copy, the recipient-name check) and its
/// own "I sent it".
class _ZelleBox extends StatelessWidget {
  const _ZelleBox({
    required this.price,
    required this.busy,
    required this.onSent,
  });

  final String price;
  final bool busy;
  final VoidCallback onSent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('access_pay_card_zelle'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance, size: 20, color: scheme.onSurface),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zelle',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      kZelleNumber,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('access_pay_card_zelle_copy'),
                icon: const Icon(Icons.copy),
                tooltip: 'Copy number',
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: kZelleNumber));
                  ScaffoldMessenger.maybeOf(context)
                    ?..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(
                        content: Text('Zelle number copied.')));
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Before sending, confirm the recipient name shows '
            '"$kZelleDisplayName".',
            softWrap: true,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _SentRow(
            sentKey: const ValueKey('access_pay_card_zelle_sent'),
            question: 'Sent $price by Zelle?',
            busy: busy,
            onSent: onSent,
          ),
        ],
      ),
    );
  }
}

/// An icon + wrapping sentence (+ an optional trailing action) in [color].
class _InlineLine extends StatelessWidget {
  const _InlineLine({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
    this.trailing,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            softWrap: true,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 4), trailing!],
      ],
    );
  }
}
