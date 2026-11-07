import { describe, expect, it } from 'vitest';
import { maskEmail, redactEmails } from './mask_email';

describe('maskEmail (merge design D6)', () => {
  it('keeps the first 2 characters and at most 8 bullets', () => {
    expect(maskEmail('carlo11rocks@gmail.com')).toBe('ca••••••••@gmail.com');
  });

  it('a 1-2 character local part keeps its first character plus one bullet', () => {
    expect(maskEmail('ab@x.org')).toBe('a•@x.org');
    expect(maskEmail('a@x.org')).toBe('a•@x.org');
  });

  it('one bullet per remaining character below the cap', () => {
    expect(maskEmail('abc@x.org')).toBe('ab•@x.org');
    expect(maskEmail('abcd@x.org')).toBe('ab••@x.org');
    expect(maskEmail('abcdefghij@x.org')).toBe('ab••••••••@x.org'); // 10 chars: 8 bullets
    expect(maskEmail('abcdefghijk@x.org')).toBe('ab••••••••@x.org'); // 11 chars: still 8
  });

  it('leaves the domain exactly as given (case and subdomains included)', () => {
    expect(maskEmail('jo@Mail.Example.CO.uk')).toBe('j•@Mail.Example.CO.uk');
  });

  it('splits at the last @ so a quoted local part cannot leak into the domain', () => {
    expect(maskEmail('we@ird@x.org')).toBe('we••••@x.org');
  });

  it('counts characters, not UTF-16 units', () => {
    expect(maskEmail('😀😀😀😀@x.org')).toBe('😀😀••@x.org');
  });

  it('trims surrounding whitespace first', () => {
    expect(maskEmail('  ab@x.org ')).toBe('a•@x.org');
  });

  it('never echoes input that is not an email', () => {
    for (const bad of ['', 'nobody', 'secret-value', '@x.org', 'abc@', '   ']) {
      const out = maskEmail(bad);
      expect(out).not.toContain('secret');
      expect(out).not.toContain('nobody');
      expect(out).not.toContain('abc');
      expect(out).toContain('•');
    }
    expect(maskEmail('@x.org')).toBe('•@x.org');
    expect(maskEmail('nobody')).toBe('••••••');
  });

  it('always yields something that contains a bullet', () => {
    expect(maskEmail('q@z.io')).toContain('•');
    expect(maskEmail('someone@z.io')).toContain('•');
  });
});

describe('redactEmails (keeps addresses out of stored errors and logs)', () => {
  it('replaces every address-looking token and leaves the rest', () => {
    expect(redactEmails('550 <carlo11rocks@gmail.com>: Recipient rejected, also x.y+z@mail.example.org!'))
      .toBe('550 <[email]>: Recipient rejected, also [email]!');
  });

  it('leaves text with no address alone and tolerates non-strings', () => {
    expect(redactEmails('connect ETIMEDOUT 10.0.0.1:587')).toBe('connect ETIMEDOUT 10.0.0.1:587');
    expect(redactEmails(undefined as unknown as string)).toBe('');
  });
});
