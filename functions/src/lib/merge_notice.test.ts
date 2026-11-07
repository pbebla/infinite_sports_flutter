import { describe, expect, it } from 'vitest';
import { parseCampaign } from './campaigns';
import {
  MERGE_PUSH_BODY, MERGE_PUSH_TITLE, mergeNoticeCampaign, mergeNoticeCampaignId, mergeNoticeEmail,
  noticeClaim,
} from './merge_notice';

describe('mergeNoticeEmail (merge design D11)', () => {
  it('has the exact subject and body text with the hint', () => {
    const { subject, html } = mergeNoticeEmail('ca••@gmail.com');
    expect(subject).toBe('Your Infinite Sports accounts were combined');
    expect(html).toBe(
      "<p>Hi, we combined your Infinite Sports accounts so all of your seasons show on one profile. " +
      "From now on, please sign in with ca••@gmail.com. " +
      "If you didn't expect this, just reply to this email.</p>");
  });

  it('HTML-escapes the hint (it is data, never markup)', () => {
    const { html } = mergeNoticeEmail('<b>x</b>&"\'@evil.test');
    expect(html).toContain('please sign in with &lt;b&gt;x&lt;/b&gt;&amp;&quot;&#39;@evil.test.');
    expect(html).not.toContain('<b>');
  });

  it('without a hint it points at "your other email" instead of an empty gap', () => {
    for (const hint of [undefined, null, '', '   ']) {
      const { html } = mergeNoticeEmail(hint);
      expect(html).toContain('please sign in with your other email.');
      expect(html).not.toMatch(/with \./);
    }
  });
});

describe('mergeNoticeCampaign (merge design D12)', () => {
  it('passes parseCampaign: a users audience of the kept uids, D12 title/body, send now', () => {
    const node = mergeNoticeCampaign(['k2', 'k1'], 1_762_400_000_000);
    const parsed = parseCampaign(node);
    expect(parsed).not.toBeNull();
    expect(parsed?.title).toBe('Your accounts were combined');
    expect(parsed?.body).toBe('All your seasons are now on this profile.');
    expect(MERGE_PUSH_TITLE).toBe('Your accounts were combined');
    expect(MERGE_PUSH_BODY).toBe('All your seasons are now on this profile.');
    expect(parsed?.audience).toEqual({ type: 'users', uids: ['k1', 'k2'] });
    expect(parsed?.sendAtMs).toBe(0);
    expect(parsed?.status).toBe('pending');
    expect(parsed?.data).toEqual({ type: 'campaign' });
  });

  it('is the Manager campaign shape: Uids as {uid: true}, CreatedAt stamped, no address anywhere', () => {
    const node = mergeNoticeCampaign(['k1', 'k1', 'k2'], 123) as Record<string, any>;
    expect(node.Audience).toEqual({ Type: 'users', Uids: { k1: true, k2: true } });
    expect(node.SendAt).toBe(0);
    expect(node.Status).toBe('pending');
    expect(node.CreatedAt).toBe(123);
    expect(JSON.stringify(node)).not.toMatch(/@/);
  });

  it('refuses an empty audience instead of writing a campaign nobody gets', () => {
    expect(() => mergeNoticeCampaign([], 1)).toThrow(/no kept accounts/);
  });
});

describe('mergeNoticeCampaignId (a re-run finds the same node)', () => {
  it('depends only on the SET of kept uids, never their order or repeats', () => {
    const a = mergeNoticeCampaignId(['k2', 'k1', 'k3']);
    expect(mergeNoticeCampaignId(['k1', 'k3', 'k2', 'k1'])).toBe(a);
    expect(mergeNoticeCampaignId(['k1', 'k2'])).not.toBe(a);
  });

  it('is a safe database key', () => {
    expect(mergeNoticeCampaignId(['k1'])).toMatch(/^merge-notice-[0-9a-f]{16}$/);
  });
});

describe('noticeClaim (the send-once transaction on MergeNotices/<uid>/Status)', () => {
  it('claims an absent Status, aborts on any existing one', () => {
    expect(noticeClaim(null)).toBe('sending');
    expect(noticeClaim(undefined)).toBe('sending');
    for (const s of ['sending', 'sent', 'failed', 'no-email', 'dry-run', '']) {
      expect(noticeClaim(s)).toBeUndefined();
    }
  });
});
