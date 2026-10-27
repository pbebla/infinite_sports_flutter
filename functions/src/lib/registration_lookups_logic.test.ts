import { describe, expect, it } from 'vitest';
import {
  collectSubmissionAnswers, firstTimerVerdict, normalizeEmail,
  normalizeJoinCode, normalizePhoneDigits, resolveJoinCodeFromTeams,
} from './registration_lookups_logic';

describe('normalizers (Dart parity)', () => {
  it('normalizeEmail trims and lowercases', () => {
    expect(normalizeEmail('  Zaya@Example.COM ')).toBe('zaya@example.com');
    expect(normalizeEmail('')).toBe('');
    expect(normalizeEmail('   ')).toBe('');
  });

  it('normalizePhoneDigits keeps digits only', () => {
    expect(normalizePhoneDigits('(408) 555-1234')).toBe('4085551234');
    expect(normalizePhoneDigits('+1 408.555.1234')).toBe('14085551234');
    expect(normalizePhoneDigits('no digits')).toBe('');
    expect(normalizePhoneDigits('')).toBe('');
  });

  it('normalizeJoinCode trims and uppercases', () => {
    expect(normalizeJoinCode(' abc123 ')).toBe('ABC123');
    expect(normalizeJoinCode('XYZ789')).toBe('XYZ789');
    expect(normalizeJoinCode('  ')).toBe('');
  });
});

describe('collectSubmissionAnswers', () => {
  const registrations = {
    reg1: {
      Config: { Status: 'open' },
      Submissions: {
        uidA: { Path: 'individual', Answers: { email: 'a@x.com', phone: '111' } },
        uidB: { Path: 'joiner', TeamId: 't1', Answers: { Email: 'B@X.com' } },
      },
    },
    reg2: {
      Config: { Status: 'closed' },
      Submissions: {
        uidC: { Path: 'captain', Answers: { phone: '(408) 555-0000' } },
      },
    },
  };

  it('collects every Answers map across every registration', () => {
    const out = collectSubmissionAnswers(registrations);
    expect(out).toHaveLength(3);
    expect(out).toContainEqual({ email: 'a@x.com', phone: '111' });
    expect(out).toContainEqual({ Email: 'B@X.com' });
    expect(out).toContainEqual({ phone: '(408) 555-0000' });
  });

  it('skips submissions without an Answers map', () => {
    const out = collectSubmissionAnswers({
      reg1: {
        Submissions: {
          uidA: { Path: 'individual' }, // no Answers
          uidB: { Path: 'individual', Answers: 'junk' }, // non-map Answers
          uidC: { Path: 'individual', Answers: { email: 'c@x.com' } },
        },
      },
    });
    expect(out).toEqual([{ email: 'c@x.com' }]);
  });

  it('skips registrations without a Submissions map', () => {
    const out = collectSubmissionAnswers({
      reg1: { Config: { Status: 'open' } }, // no Submissions at all
      reg2: { Submissions: 'junk' },
      reg3: { Submissions: { uidA: { Answers: { email: 'z@x.com' } } } },
    });
    expect(out).toEqual([{ email: 'z@x.com' }]);
  });

  it('returns [] for null/scalars/arrays (RTDB coercion) without crashing', () => {
    expect(collectSubmissionAnswers(null)).toEqual([]);
    expect(collectSubmissionAnswers(undefined)).toEqual([]);
    expect(collectSubmissionAnswers('junk')).toEqual([]);
    expect(collectSubmissionAnswers([{ Submissions: {} }])).toEqual([]);
  });

  it('skips array-coerced inner nodes without crashing', () => {
    const out = collectSubmissionAnswers({
      regA: [{ Answers: { email: 'in-array@x.com' } }], // coerced registration
      regB: { Submissions: [{ Answers: { email: 'in-array2@x.com' } }] },
      regC: {
        Submissions: {
          uidA: { Answers: ['coerced-answers'] }, // coerced Answers
          uidB: { Answers: { email: 'ok@x.com' } },
        },
      },
    });
    expect(out).toEqual([{ email: 'ok@x.com' }]);
  });
});

describe('firstTimerVerdict', () => {
  const prior = [
    { email: 'zaya@example.com', phone: '(408) 555-1234' },
    { Email: 'CAP@Example.com', Phone: '650 555 0000' },
    { firstName: 'No', lastName: 'Contact' }, // no email/phone keys at all
  ];

  it('is a first-timer when neither signal matches', () => {
    expect(firstTimerVerdict('new@example.com', '999-999-9999', prior)).toEqual({
      isFirstTimer: true, matchedByEmail: false, matchedByPhone: false,
    });
  });

  it('matches by email, normalized on both sides', () => {
    expect(firstTimerVerdict(' ZAYA@Example.COM ', '', prior)).toEqual({
      isFirstTimer: false, matchedByEmail: true, matchedByPhone: false,
    });
  });

  it('matches by phone, digits-only on both sides', () => {
    expect(firstTimerVerdict('', '408.555.1234', prior)).toEqual({
      isFirstTimer: false, matchedByEmail: false, matchedByPhone: true,
    });
  });

  it('reports both signals when both match', () => {
    expect(firstTimerVerdict('zaya@example.com', '4085551234', prior)).toEqual({
      isFirstTimer: false, matchedByEmail: true, matchedByPhone: true,
    });
  });

  it('reads capitalized Email/Phone answer keys too', () => {
    expect(firstTimerVerdict('cap@example.com', '', prior).matchedByEmail)
      .toBe(true);
    expect(firstTimerVerdict('', '(650) 555-0000', prior).matchedByPhone)
      .toBe(true);
  });

  it('an empty input signal never matches anything', () => {
    const withEmpty = [{ email: '', phone: '' }];
    expect(firstTimerVerdict('', '', withEmpty)).toEqual({
      isFirstTimer: true, matchedByEmail: false, matchedByPhone: false,
    });
    // Whitespace-only input normalizes to empty too.
    expect(firstTimerVerdict('   ', ' - ', withEmpty).isFirstTimer).toBe(true);
  });

  it('empty inputs yield first-timer even with real prior submissions', () => {
    expect(firstTimerVerdict('', '', prior).isFirstTimer).toBe(true);
  });

  it("a present-but-empty 'email' key shadows 'Email' (Dart ?? parity)", () => {
    // Dart: (sub['email'] ?? sub['Email'] ?? '') — ?? fires only on null, so
    // email:'' hides Email. The port must behave identically.
    const shadowed = [{ email: '', Email: 'shadowed@example.com' }];
    expect(firstTimerVerdict('shadowed@example.com', '', shadowed).isFirstTimer)
      .toBe(true);
  });

  it('handles an empty prior list', () => {
    expect(firstTimerVerdict('a@b.c', '123', [])).toEqual({
      isFirstTimer: true, matchedByEmail: false, matchedByPhone: false,
    });
  });

  it('stringifies non-string answer values (Dart toString parity)', () => {
    const numericPhone = [{ phone: 4085551234 }];
    expect(firstTimerVerdict('', '408-555-1234', numericPhone).matchedByPhone)
      .toBe(true);
  });
});

describe('resolveJoinCodeFromTeams', () => {
  const teams = {
    tApproved: {
      Name: 'The Boys',
      CaptainUid: 'cap1',
      Status: 'approved',
      JoinCode: 'ABC234',
      CodeWaivesPayment: true,
      CreatedAt: 1,
    },
    tPending: {
      Name: 'Pending FC',
      CaptainUid: 'cap2',
      Status: 'pending',
      JoinCode: 'PEND99',
      CodeWaivesPayment: false,
      CreatedAt: 2,
    },
    tRejected: {
      Name: 'Rejected United',
      CaptainUid: 'cap3',
      Status: 'rejected',
      JoinCode: 'REJ222',
      CodeWaivesPayment: false,
      CreatedAt: 3,
    },
    tNoCode: {
      Name: 'Codeless',
      CaptainUid: 'cap4',
      Status: 'approved',
      CodeWaivesPayment: false,
      CreatedAt: 4,
    },
  };

  it('resolves an approved team with the matched team only', () => {
    expect(resolveJoinCodeFromTeams(teams, 'ABC234')).toEqual({
      found: true,
      status: 'ok',
      teamId: 'tApproved',
      teamName: 'The Boys',
      codeWaivesPayment: true,
    });
  });

  it('matches case-insensitively and trimmed, both sides normalized', () => {
    expect(resolveJoinCodeFromTeams(teams, ' abc234 ').found).toBe(true);
    const lowerStored = {
      t1: { Name: 'Lower', Status: 'approved', JoinCode: ' xyz789 ' },
    };
    expect(resolveJoinCodeFromTeams(lowerStored, 'XYZ789').found).toBe(true);
  });

  it("a pending team's code is notApproved with NO team details", () => {
    const res = resolveJoinCodeFromTeams(teams, 'PEND99');
    expect(res).toEqual({ found: false, status: 'notApproved' });
    expect(Object.keys(res).sort()).toEqual(['found', 'status']);
  });

  it("a rejected team's code is notApproved too (Dart isApproved parity)", () => {
    expect(resolveJoinCodeFromTeams(teams, 'REJ222'))
      .toEqual({ found: false, status: 'notApproved' });
  });

  it('an unknown code is notFound', () => {
    expect(resolveJoinCodeFromTeams(teams, 'NOPE42'))
      .toEqual({ found: false, status: 'notFound' });
  });

  it('an empty or whitespace code is notFound, even if a team had an empty code', () => {
    expect(resolveJoinCodeFromTeams(teams, ''))
      .toEqual({ found: false, status: 'notFound' });
    expect(resolveJoinCodeFromTeams(teams, '   '))
      .toEqual({ found: false, status: 'notFound' });
  });

  it('an approved team always beats a non-approved one with the same code', () => {
    const dup = {
      aPending: { Name: 'First Listed', Status: 'pending', JoinCode: 'SAME77' },
      bApproved: {
        Name: 'Real Team', Status: 'approved', JoinCode: 'SAME77',
        CodeWaivesPayment: false,
      },
    };
    const res = resolveJoinCodeFromTeams(dup, 'SAME77');
    expect(res).toEqual({
      found: true, status: 'ok', teamId: 'bApproved', teamName: 'Real Team',
      codeWaivesPayment: false,
    });
  });

  it('an unknown Status parses as pending (fromNode parity) -> notApproved', () => {
    const weird = {
      t1: { Name: 'Weird', Status: 'activeish', JoinCode: 'WEIRD9' },
    };
    expect(resolveJoinCodeFromTeams(weird, 'WEIRD9'))
      .toEqual({ found: false, status: 'notApproved' });
  });

  it('skips malformed team nodes (non-map, missing Name) without crashing', () => {
    const messy = {
      junk: 'not a team',
      noName: { Status: 'approved', JoinCode: 'NONAME' },
      coerced: [{ Name: 'In Array', Status: 'approved', JoinCode: 'COERCE' }],
      ok: { Name: 'Fine', Status: 'approved', JoinCode: 'FINE55' },
    };
    expect(resolveJoinCodeFromTeams(messy, 'NONAME'))
      .toEqual({ found: false, status: 'notFound' });
    expect(resolveJoinCodeFromTeams(messy, 'COERCE'))
      .toEqual({ found: false, status: 'notFound' });
    expect(resolveJoinCodeFromTeams(messy, 'FINE55').found).toBe(true);
  });

  it('a non-map Teams node (missing/junk/array) is notFound without crashing', () => {
    expect(resolveJoinCodeFromTeams(null, 'ABC234'))
      .toEqual({ found: false, status: 'notFound' });
    expect(resolveJoinCodeFromTeams(undefined, 'ABC234'))
      .toEqual({ found: false, status: 'notFound' });
    expect(resolveJoinCodeFromTeams('junk', 'ABC234'))
      .toEqual({ found: false, status: 'notFound' });
    expect(resolveJoinCodeFromTeams(
      [{ Name: 'Arr', Status: 'approved', JoinCode: 'ABC234' }], 'ABC234'))
      .toEqual({ found: false, status: 'notFound' });
  });

  it('codeWaivesPayment is true only for a literal true', () => {
    const t = {
      t1: {
        Name: 'T', Status: 'approved', JoinCode: 'WAIVE1',
        CodeWaivesPayment: 'true',
      },
    };
    const res = resolveJoinCodeFromTeams(t, 'WAIVE1');
    expect(res.found).toBe(true);
    if (res.found) expect(res.codeWaivesPayment).toBe(false);
  });

  it('a numeric stored JoinCode matches its string form (Dart toString parity)', () => {
    const t = { t1: { Name: 'Numeric', Status: 'approved', JoinCode: 234567 } };
    expect(resolveJoinCodeFromTeams(t, '234567').found).toBe(true);
  });

  it("NEVER leaks other teams' codes or names in any outcome", () => {
    for (const code of ['ABC234', 'PEND99', 'REJ222', 'NOPE42', '']) {
      const json = JSON.stringify(resolveJoinCodeFromTeams(teams, code));
      // No outcome may carry any OTHER team's join code...
      for (const other of ['PEND99', 'REJ222']) {
        if (normalizeJoinCode(code) !== other) expect(json).not.toContain(other);
      }
      expect(json).not.toContain('ABC234'); // even the matched code never echoes back
      // ...nor any non-matched team's name.
      if (normalizeJoinCode(code) !== 'ABC234') {
        expect(json).not.toContain('The Boys');
      }
      expect(json).not.toContain('Pending FC');
      expect(json).not.toContain('Rejected United');
      expect(json).not.toContain('Codeless');
    }
  });
});
