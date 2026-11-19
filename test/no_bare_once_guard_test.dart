// Fresh reads (plan 2026-11-13-fresh-reads.md, Task 5): no bare `once()`
// anywhere in lib/ except the fresh-read helpers themselves.
//
// A one-shot `once()` answers from the phone's saved copy of the database
// and does not reliably renew it (measured: docs/superpowers/plans/assets/
// 2026-11-13-fresh-read-probe.md), so a screen built on it can show old data
// indefinitely, and a decision built on it can act on old data. Every read
// goes through lib/misc/fresh_read.dart instead:
//   • refreshingOnce / refreshingValue — DISPLAY: answers from the saved copy
//     at once and keeps listening until the server has answered;
//   • serverFirstOnce / serverFirstValue — DECISIONS: the server's answer
//     (bounded), else the saved copy marked fromServer: false.
// (`.get()` stays banned too: it returns wrong data on iOS.)
//
// tool/ (the fresh-read probe) is outside lib/ and is not scanned. Comment
// lines are ignored.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no file under lib/ calls once() except lib/misc/fresh_read.dart', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final path = file.path.replaceAll('\\', '/');
      if (path == 'lib/misc/fresh_read.dart') continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//')) continue;
        if (RegExp(r'\.once\s*\(').hasMatch(line)) {
          offenders.add('$path:${i + 1}: $line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Bare once() answers from the phone\'s saved copy and never '
            'renews it. Use refreshingOnce/refreshingValue (display) or '
            'serverFirstOnce/serverFirstValue (decisions) from '
            'lib/misc/fresh_read.dart:\n${offenders.join('\n')}');
  });

  test('the scan sees lib/ (guards the guard)', () {
    expect(File('lib/misc/fresh_read.dart').existsSync(), isTrue);
    expect(
        File('lib/misc/fresh_read.dart')
            .readAsStringSync()
            .contains(RegExp(r'\.once\s*\(')),
        isTrue,
        reason: 'the helper itself issues the barrier once()');
  });
}
