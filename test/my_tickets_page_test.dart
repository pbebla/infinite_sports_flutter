// Widget tests for My Tickets + the ticket thread view
// (lib/support/my_tickets_page.dart, zaya-support). Firebase-free: the
// ticketNumsStream / ticketStreamOf / replyOverride / prefill* seams replace
// every Firebase touch (insiders_info_page_test.dart pattern). Fake streams
// are created fresh per call because the page hands the thread page its own
// stream.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/support/my_tickets_page.dart';
import 'package:infinite_sports_flutter/support/support_models.dart';

SupportTicket _ticket(
  int num, {
  String status = 'open',
  String category = 'bug',
  String message = 'Something broke.',
  List<SupportThreadMessage> thread = const [],
}) =>
    SupportTicket(
      num: num,
      uid: 'uid123',
      name: 'Zaya Arami',
      category: category,
      message: message,
      status: status,
      thread: thread,
    );

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  group('MyTicketsPage list', () {
    testWidgets(
        'renders every ticket newest-first with plain-word statuses and the '
        'first message line', (tester) async {
      final tickets = {
        3: _ticket(3, status: 'answered', message: 'Crash on kickoff.\nMore.'),
        2: _ticket(2, status: 'waiting', category: 'help'),
        1: _ticket(1, status: 'in_progress', category: 'suggestion'),
      };
      await tester.pumpWidget(wrap(MyTicketsPage(
        ticketNumsStream: Stream.value(const [3, 2, 1]),
        ticketStreamOf: (n) => Stream.value(tickets[n]),
        prefillUid: 'uid123',
        prefillName: 'Zaya Arami',
      )));
      await tester.pump();
      await tester.pump();

      // Plain words, never raw status keys (owner decision #6).
      expect(find.text('Answered'), findsOneWidget);
      expect(find.text('Waiting for your reply'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('in_progress'), findsNothing);

      // #num + first line of the message + category emoji.
      expect(find.text('#3'), findsOneWidget);
      expect(find.text('Crash on kickoff.'), findsOneWidget);
      expect(find.text('🐞'), findsOneWidget);
      expect(find.text('❓'), findsOneWidget);
      expect(find.text('💡'), findsOneWidget);

      // Newest (highest num) listed first.
      final y3 = tester
          .getTopLeft(find.byKey(const ValueKey('support_ticket_row_3')))
          .dy;
      final y1 = tester
          .getTopLeft(find.byKey(const ValueKey('support_ticket_row_1')))
          .dy;
      expect(y3, lessThan(y1));
    });

    testWidgets('empty index shows the no-tickets body', (tester) async {
      await tester.pumpWidget(wrap(MyTicketsPage(
        ticketNumsStream: Stream.value(const []),
        ticketStreamOf: (n) => Stream.value(null),
        prefillUid: 'uid123',
        prefillName: 'Zaya Arami',
      )));
      await tester.pump();

      expect(find.text('No tickets yet'), findsOneWidget);
    });

    testWidgets('tapping a row opens the thread view for that ticket',
        (tester) async {
      await tester.pumpWidget(wrap(MyTicketsPage(
        ticketNumsStream: Stream.value(const [7]),
        ticketStreamOf: (n) =>
            Stream.value(_ticket(7, message: 'Opening message.')),
        prefillUid: 'uid123',
        prefillName: 'Zaya Arami',
      )));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('support_ticket_row_7')));
      await tester.pumpAndSettle();

      expect(find.text('Ticket #7'), findsOneWidget);
      expect(find.text('Opening message.'), findsOneWidget);
      expect(find.byKey(const ValueKey('support_reply_field')), findsOneWidget);
    });
  });

  group('TicketThreadPage', () {
    testWidgets(
        'renders the opening Message as the first bubble, then user and '
        'admin bubbles — admin styled with its label', (tester) async {
      await tester.pumpWidget(wrap(TicketThreadPage(
        num: 9,
        ticketStream: Stream.value(_ticket(
          9,
          message: 'The table page is blank.',
          thread: const [
            SupportThreadMessage(
                id: '-a', from: 'user', name: 'Zaya', text: 'Still blank.', at: 100),
            SupportThreadMessage(
                id: '-b',
                from: 'admin',
                name: 'IS',
                text: 'Fixed in the next update!',
                at: 200),
          ],
        )),
        prefillUid: 'uid123',
        prefillName: 'Zaya Arami',
      )));
      await tester.pump();

      // Nothing hidden that shouldn't be: opening message + both replies
      // render (internal notes live in the admin-only Notes/ subtree and
      // are never inside Thread in the first place).
      expect(find.text('The table page is blank.'), findsOneWidget);
      expect(find.text('Still blank.'), findsOneWidget);
      expect(find.text('Fixed in the next update!'), findsOneWidget);
      // Admin bubble is visibly distinct via its sender label.
      expect(find.text('Infinite Sports'), findsOneWidget);
    });

    testWidgets('reply sends through replyOverride and clears the field',
        (tester) async {
      int? capturedNum;
      String? capturedUid;
      String? capturedName;
      String? capturedText;
      await tester.pumpWidget(wrap(TicketThreadPage(
        num: 9,
        ticketStream: Stream.value(_ticket(9)),
        replyOverride: (n,
            {required uid, required name, required text}) async {
          capturedNum = n;
          capturedUid = uid;
          capturedName = name;
          capturedText = text;
        },
        prefillUid: 'uid123',
        prefillName: 'Zaya Arami',
      )));
      await tester.pump();

      // Empty reply: send disabled.
      IconButton sendButton() => tester.widget<IconButton>(
          find.byKey(const ValueKey('support_send_reply_button')));
      expect(sendButton().onPressed, isNull);

      await tester.enterText(
          find.byKey(const ValueKey('support_reply_field')), '  Thanks!  ');
      await tester.pump();
      expect(sendButton().onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('support_send_reply_button')));
      await tester.pump();
      await tester.pump();

      expect(capturedNum, 9);
      expect(capturedUid, 'uid123');
      expect(capturedName, 'Zaya Arami');
      expect(capturedText, 'Thanks!'); // trimmed
      final field = tester.widget<TextField>(
          find.byKey(const ValueKey('support_reply_field')));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets(
        'closed ticket replaces the reply box with the gentle closed note',
        (tester) async {
      await tester.pumpWidget(wrap(TicketThreadPage(
        num: 4,
        ticketStream: Stream.value(_ticket(4, status: 'closed')),
        prefillUid: 'uid123',
        prefillName: 'Zaya Arami',
      )));
      await tester.pump();

      expect(find.byKey(const ValueKey('support_closed_note')), findsOneWidget);
      expect(
          find.text('This ticket is closed — open a new one if something '
              'else comes up.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('support_reply_field')), findsNothing);
      expect(find.byKey(const ValueKey('support_send_reply_button')),
          findsNothing);
    });
  });
}
