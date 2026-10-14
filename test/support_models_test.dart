// Unit tests for the pure support-ticket helpers
// (lib/support/support_models.dart, zaya-support) — no Flutter/Firebase,
// mirrors test style of the insider model tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/support/support_models.dart';

void main() {
  group('recentTicketCount (soft 6/hour rate-limit input)', () {
    const hour = 60 * 60 * 1000;
    const now = 1760000000000;

    test('counts only stamps within the last hour', () {
      final ats = [
        now - 1, // just now
        now - hour + 1000, // 59m59s ago — still inside
        now - hour, // exactly an hour ago — outside
        now - 2 * hour, // old
      ];
      expect(recentTicketCount(ats, now), 2);
    });

    test('empty input counts zero', () {
      expect(recentTicketCount(const [], now), 0);
    });

    test('future stamps (clock skew) still count as recent', () {
      expect(recentTicketCount([now + 5000], now), 1);
    });

    test('six within the hour reaches the limit constant', () {
      final ats = List.generate(6, (i) => now - i * 1000);
      expect(recentTicketCount(ats, now) >= kSupportRateLimitPerHour, isTrue);
    });
  });

  group('capScreenshots (max-5 cap)', () {
    test('appends while under the cap', () {
      expect(capScreenshots(['a'], ['b', 'c']), ['a', 'b', 'c']);
    });

    test('drops picks beyond the cap, in pick order', () {
      final out =
          capScreenshots(['a', 'b', 'c', 'd'], ['e', 'f', 'g']);
      expect(out, ['a', 'b', 'c', 'd', 'e']);
      expect(out.length, kMaxScreenshots);
    });

    test('a full list accepts nothing more', () {
      final full = ['1', '2', '3', '4', '5'];
      expect(capScreenshots(full, ['6']), full);
    });

    test('never mutates its inputs', () {
      final current = ['a'];
      final picked = ['b'];
      capScreenshots(current, picked);
      expect(current, ['a']);
      expect(picked, ['b']);
    });

    test('downscale/upload constants match the owner-locked spec', () {
      expect(kScreenshotMaxDimension, 1600);
      expect(kScreenshotJpegQuality, 80);
      expect(kMaxScreenshots, 5);
      expect(kSupportMessageMaxLength, 5000);
    });
  });

  group('supportStatusLabel (plain words only)', () {
    test('maps every stored status to the owner-locked phrasing', () {
      expect(supportStatusLabel('open'), 'Open');
      expect(supportStatusLabel('in_progress'), 'In progress');
      expect(supportStatusLabel('waiting'), 'Waiting for your reply');
      expect(supportStatusLabel('answered'), 'Answered');
      expect(supportStatusLabel('closed'), 'Closed');
    });

    test('unknown/missing statuses read as Open (tickets are born open)', () {
      expect(supportStatusLabel(''), 'Open');
      expect(supportStatusLabel('nonsense'), 'Open');
    });
  });

  group('firstMessageLine', () {
    test('takes the first non-empty line, trimmed', () {
      expect(firstMessageLine('  The app froze.  \nSecond line'),
          'The app froze.');
      expect(firstMessageLine('\n\n  late start\nmore'), 'late start');
    });

    test('empty message yields empty string', () {
      expect(firstMessageLine(''), '');
      expect(firstMessageLine('\n\n'), '');
    });
  });

  group('categories', () {
    test('six owner-locked categories with their emoji', () {
      expect(kSupportCategories.map((c) => c.key).toList(),
          ['suggestion', 'comment', 'bug', 'help', 'account', 'other']);
      expect(categoryEmoji('bug'), '🐞');
      expect(categoryEmoji('suggestion'), '💡');
      expect(categoryTitle('account'), 'Account or access');
    });

    test('unknown category reads as Something else', () {
      expect(categoryEmoji('mystery'), '✨');
      expect(categoryTitle('mystery'), 'Something else');
    });
  });

  group('ticketNumsFromIndex', () {
    test('parses keys newest (highest) first, skipping junk', () {
      expect(
          ticketNumsFromIndex({'3': true, '12': true, '7': true, 'x': true}),
          [12, 7, 3]);
    });

    test('false/null markers and non-map nodes yield nothing', () {
      expect(ticketNumsFromIndex({'3': false}), isEmpty);
      expect(ticketNumsFromIndex(null), isEmpty);
      expect(ticketNumsFromIndex('nope'), isEmpty);
    });
  });

  group('parseScreenshotUrls (RTDB list/map duality)', () {
    test('real lists pass through, null holes skipped', () {
      expect(parseScreenshotUrls(['u1', null, 'u2']), ['u1', 'u2']);
    });

    test('{0:.., 1:..} maps normalize in numeric key order', () {
      expect(parseScreenshotUrls({'1': 'b', '0': 'a', '10': 'c'}),
          ['a', 'b', 'c']);
    });

    test('anything else is empty', () {
      expect(parseScreenshotUrls(null), isEmpty);
      expect(parseScreenshotUrls(42), isEmpty);
    });
  });

  group('SupportTicket.fromFirebase', () {
    test('parses the full node, including the PascalCase Message field', () {
      final ticket = SupportTicket.fromFirebase(17, {
        'Num': 17,
        'Uid': 'u1',
        'Name': 'Zaya Arami',
        'Email': 'z@example.com',
        'Category': 'bug',
        'Message': 'The score page crashed.\nTwice.',
        'Status': 'answered',
        'CreatedAt': 1000,
        'UpdatedAt': 2000,
        'AppVersion': '3.0.0+10',
        'Platform': 'Android',
        'Device': 'android 14',
        'Screen': 'Drawer',
        'Screenshots': ['https://x/img_0.jpg'],
      })!;
      expect(ticket.num, 17);
      expect(ticket.uid, 'u1');
      expect(ticket.name, 'Zaya Arami');
      expect(ticket.message, 'The score page crashed.\nTwice.');
      expect(ticket.status, 'answered');
      expect(ticket.isClosed, isFalse);
      expect(ticket.screenshots, ['https://x/img_0.jpg']);
      expect(ticket.thread, isEmpty);
    });

    test('thread replies sort oldest first by At (push-id tie-break)', () {
      final ticket = SupportTicket.fromFirebase(1, {
        'Message': 'opening',
        'Thread': {
          '-b': {'From': 'admin', 'Name': 'IS', 'Text': 'second', 'At': 200},
          '-a': {'From': 'user', 'Name': 'Z', 'Text': 'first', 'At': 100},
          '-c': {'From': 'user', 'Text': 'tie-later', 'At': 200},
        },
      })!;
      expect(ticket.thread.map((m) => m.text).toList(),
          ['first', 'second', 'tie-later']);
      expect(ticket.thread[1].isAdmin, isTrue);
      expect(ticket.thread[0].isUser, isTrue);
    });

    test('non-map raw is null; empty map parses to defaults', () {
      expect(SupportTicket.fromFirebase(1, null), isNull);
      final empty = SupportTicket.fromFirebase(1, {})!;
      expect(empty.status, 'open');
      expect(empty.message, '');
    });

    test('closed status flips isClosed', () {
      expect(
          SupportTicket.fromFirebase(1, {'Status': 'closed'})!.isClosed, isTrue);
    });
  });
}
