import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/support/support_models.dart';
import 'package:infinite_sports_flutter/support/support_service.dart';
import 'package:intl/intl.dart';

/// Status pill color, theme-safe (house light+dark rule): darker shades on
/// the light surface, lighter shades on the dark one — never a single
/// hardcoded light-palette fill.
Color supportStatusColor(String status, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  switch (status.trim().toLowerCase()) {
    case 'in_progress':
      return dark ? Colors.orange.shade300 : Colors.orange.shade800;
    case 'waiting':
      return dark ? Colors.purple.shade200 : Colors.purple.shade700;
    case 'answered':
      return dark ? Colors.green.shade400 : Colors.green.shade700;
    case 'closed':
      return dark ? Colors.grey.shade500 : Colors.grey.shade600;
    default: // open
      return dark ? Colors.lightBlue.shade300 : Colors.blue.shade700;
  }
}

/// Live list of the signed-in player's own tickets, newest first (spec
/// decision #6): #num, category emoji, the first line of the opening
/// message, and the status in plain words. Tapping a row opens
/// [TicketThreadPage].
///
/// Streams only (iOS-parity house rule). Test seams ([ticketNumsStream],
/// [ticketStreamOf], [replyOverride], `prefill*`) replace every Firebase
/// touch — insiders_info_page.dart pattern.
class MyTicketsPage extends StatefulWidget {
  const MyTicketsPage({
    super.key,
    this.ticketNumsStream,
    this.ticketStreamOf,
    this.replyOverride,
    this.prefillUid,
    this.prefillName,
  });

  /// Test seam: replaces [SupportService.watchMyTicketNums] for the
  /// signed-in uid.
  final Stream<List<int>>? ticketNumsStream;

  /// Test seam: replaces [SupportService.watchTicket] per ticket number
  /// (also handed down to the thread page a row tap pushes).
  final Stream<SupportTicket?> Function(int num)? ticketStreamOf;

  /// Test seam: replaces [SupportService.addUserReply] (handed down to the
  /// thread page).
  final Future<void> Function(int num,
      {required String uid, required String name, required String text})?
      replyOverride;

  /// Test seams for the reply identity — production reads FirebaseAuth.
  final String? prefillUid;
  final String? prefillName;

  @override
  State<MyTicketsPage> createState() => _MyTicketsPageState();
}

class _MyTicketsPageState extends State<MyTicketsPage> {
  late final Stream<List<int>> _nums;

  /// One stream per row, created lazily and KEPT — a stable identity means
  /// each row's StreamBuilder subscribes once instead of resubscribing on
  /// every list rebuild.
  final Map<int, Stream<SupportTicket?>> _rowStreams = {};

  @override
  void initState() {
    super.initState();
    // `??` short-circuits: when a test supplies ticketNumsStream,
    // FirebaseAuth.instance is never touched.
    _nums = widget.ticketNumsStream ??
        SupportService.watchMyTicketNums(
            FirebaseAuth.instance.currentUser?.uid ?? '');
  }

  Stream<SupportTicket?> _freshTicketStream(int num) =>
      (widget.ticketStreamOf ?? SupportService.watchTicket)(num);

  Stream<SupportTicket?> _rowTicketStream(int num) =>
      _rowStreams.putIfAbsent(num, () => _freshTicketStream(num));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tickets'),
        backgroundColor: TournamentColors.headerBackground(context),
        foregroundColor: TournamentColors.headerForeground(context),
      ),
      body: StreamBuilder<List<int>>(
        stream: _nums,
        builder: (context, snapshot) {
          final nums = snapshot.data;
          if (nums == null) {
            return Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary));
          }
          if (nums.isEmpty) return _emptyBody(context);
          return ListView.builder(
            // Glass-navbar clearance (house rule).
            padding: EdgeInsets.only(
                top: 8, bottom: 8 + MediaQuery.paddingOf(context).bottom),
            itemCount: nums.length,
            itemBuilder: (context, index) {
              // Inner Builder wrap (house rule: ListView.builder rows
              // reading Theme).
              return Builder(
                  builder: (context) => _ticketRow(context, nums[index]));
            },
          );
        },
      ),
    );
  }

  Widget _emptyBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No tickets yet',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Anything you send from Help & Feedback shows up here, '
              'along with our replies.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ticketRow(BuildContext context, int num) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<SupportTicket?>(
      stream: _rowTicketStream(num),
      builder: (context, snapshot) {
        final ticket = snapshot.data;
        if (ticket == null) return const SizedBox.shrink();
        final statusColor =
            supportStatusColor(ticket.status, Theme.of(context).brightness);
        return ListTile(
          key: ValueKey('support_ticket_row_$num'),
          leading:
              Text(categoryEmoji(ticket.category), style: const TextStyle(fontSize: 24)),
          title: Text(
            // First line only, but WRAPPING, never ellipsized (house rule).
            firstMessageLine(ticket.message),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    supportStatusLabel(ticket.status),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                Text('#$num',
                    style:
                        TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) {
              return TicketThreadPage(
                num: num,
                // A FRESH stream, not the row's — the row's subscription
                // stays alive underneath the pushed page.
                ticketStream: _freshTicketStream(num),
                replyOverride: widget.replyOverride,
                prefillUid: widget.prefillUid,
                prefillName: widget.prefillName,
              );
            }));
          },
        );
      },
    );
  }
}

/// One ticket's conversation (spec decision #6): the opening Message as the
/// player's first bubble, then the Thread replies in order — admin bubbles
/// styled distinctly — with the ticket's screenshots as tappable thumbnails
/// and a reply box pinned at the bottom. The reply box gives way to a gentle
/// closed note once Status is 'closed'. Internal notes live in the
/// admin-only Notes/ subtree (never inside Thread), and the bubble builder
/// additionally skips any From it doesn't recognize.
class TicketThreadPage extends StatefulWidget {
  const TicketThreadPage({
    super.key,
    required this.num,
    this.ticketStream,
    this.replyOverride,
    this.prefillUid,
    this.prefillName,
  });

  final int num;

  /// Test seam: replaces [SupportService.watchTicket].
  final Stream<SupportTicket?>? ticketStream;

  /// Test seam: replaces [SupportService.addUserReply].
  final Future<void> Function(int num,
      {required String uid, required String name, required String text})?
      replyOverride;

  /// Test seams for the reply identity — production reads FirebaseAuth.
  final String? prefillUid;
  final String? prefillName;

  @override
  State<TicketThreadPage> createState() => _TicketThreadPageState();
}

class _TicketThreadPageState extends State<TicketThreadPage> {
  // Owned by this State, disposed in dispose — never a dialog-scoped
  // controller (house dialog-controller rule).
  final TextEditingController _replyController = TextEditingController();
  late final Stream<SupportTicket?> _ticketStream;
  bool _sending = false;

  String _uid = '';
  String _name = '';

  @override
  void initState() {
    super.initState();
    _replyController.addListener(() => setState(() {}));
    // `??` short-circuits (tests never touch FirebaseAuth).
    _ticketStream =
        widget.ticketStream ?? SupportService.watchTicket(widget.num);
    if (widget.prefillUid == null || widget.prefillName == null) {
      final user = FirebaseAuth.instance.currentUser;
      _uid = widget.prefillUid ?? user?.uid ?? '';
      _name = widget.prefillName ?? user?.displayName ?? '';
    } else {
      _uid = widget.prefillUid!;
      _name = widget.prefillName!;
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final reply = widget.replyOverride ??
          (int n, {required String uid, required String name, required String text}) =>
              SupportService.addUserReply(n, uid: uid, name: name, text: text);
      await reply(widget.num, uid: _uid, name: _name, text: text);
      _replyController.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Something went wrong. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ticket #${widget.num}'),
        backgroundColor: TournamentColors.headerBackground(context),
        foregroundColor: TournamentColors.headerForeground(context),
      ),
      body: SafeArea(
        child: StreamBuilder<SupportTicket?>(
          stream: _ticketStream,
          builder: (context, snapshot) {
            final ticket = snapshot.data;
            if (ticket == null) {
              return Center(
                  child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary));
            }
            return Column(
              children: [
                Expanded(child: _conversation(context, ticket)),
                _composer(context, ticket),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _conversation(BuildContext context, SupportTicket ticket) {
    final children = <Widget>[
      // The opening message is the player's first bubble (Thread holds only
      // replies — the node's `Message` field carries it).
      _bubble(
        context,
        isUser: true,
        label: null,
        text: ticket.message,
        at: ticket.createdAt,
        screenshots: ticket.screenshots,
      ),
      for (final msg in ticket.thread)
        if (msg.isUser || msg.isAdmin)
          _bubble(
            context,
            isUser: msg.isUser,
            label: msg.isAdmin ? 'Infinite Sports' : null,
            text: msg.text,
            at: msg.at,
            screenshots: msg.screenshots,
          ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      children: children,
    );
  }

  Widget _bubble(
    BuildContext context, {
    required bool isUser,
    required String? label,
    required String text,
    required int at,
    required List<String> screenshots,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = isUser ? scheme.onPrimaryContainer : scheme.onSurface;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isUser ? 14 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 14),
            ),
            // Admin bubbles carry a distinct gold/primary edge.
            border: isUser
                ? null
                : Border.all(color: scheme.primary.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(label,
                      style: TextStyle(
                          color: scheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              // Wraps, never ellipsizes (house rule).
              Text(text, style: TextStyle(color: fg)),
              if (screenshots.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final url in screenshots)
                        _screenshotThumb(context, url),
                    ],
                  ),
                ),
              if (at > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('MMM d, h:mm a')
                        .format(DateTime.fromMillisecondsSinceEpoch(at)),
                    style: TextStyle(
                        color: fg.withValues(alpha: 0.6), fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _screenshotThumb(BuildContext context, String url) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) {
          return _FullScreenImagePage(url: url);
        }));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (context, _, __) => Container(
            width: 72,
            height: 72,
            color: scheme.surfaceContainerHighest,
            child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _composer(BuildContext context, SupportTicket ticket) {
    final scheme = Theme.of(context).colorScheme;
    // Glass-navbar clearance (house rule) — the composer is the page's
    // bottom-most element.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    if (ticket.isClosed) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomInset),
        child: Container(
          key: const ValueKey('support_closed_note'),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'This ticket is closed — open a new one if something else '
            'comes up.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 8 + bottomInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('support_reply_field'),
              controller: _replyController,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                hintText: 'Reply…',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            key: const ValueKey('support_send_reply_button'),
            style: IconButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
            ),
            onPressed:
                (_sending || _replyController.text.trim().isEmpty)
                    ? null
                    : _sendReply,
            icon: _sending
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: scheme.onPrimary),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

/// Minimal pinch-zoomable full-screen viewer for a ticket screenshot. Black
/// in both themes (an image lightbox, not a surface).
class _FullScreenImagePage extends StatelessWidget {
  const _FullScreenImagePage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (context, _, __) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 56),
          ),
        ),
      ),
    );
  }
}
