/** The masked form of an email address (merge design D6), shared by the
 *  duplicate-account merge tool and the merge-notice trigger so a hint is
 *  always built the same way and an address is never stored whole.
 *
 *  The local part keeps its first 2 characters, then one `•` for every
 *  remaining character (at most 8); a local part of 1-2 characters keeps its
 *  first character and gets one `•`. The domain is unchanged:
 *    carlo11rocks@gmail.com -> ca••••••••@gmail.com
 *    ab@x.org               -> a•@x.org
 *    a@x.org                -> a•@x.org
 *
 *  Pure. Splits at the LAST `@`, counts characters (not UTF-16 units), and
 *  never echoes input that is not an email: with no `@` or no domain the
 *  result is a bare run of bullets. */
export const MASK_BULLET = '•';
const MAX_BULLETS = 8;
const NOT_AN_EMAIL = MASK_BULLET.repeat(6);

export function maskEmail(email: string): string {
  const trimmed = String(email ?? '').trim();
  const at = trimmed.lastIndexOf('@');
  if (at < 0 || at === trimmed.length - 1) return NOT_AN_EMAIL;
  const local = Array.from(trimmed.slice(0, at));
  const domain = trimmed.slice(at + 1);
  if (local.length === 0) return `${MASK_BULLET}@${domain}`;
  if (local.length <= 2) return `${local[0]}${MASK_BULLET}@${domain}`;
  const bullets = Math.min(local.length - 2, MAX_BULLETS);
  return `${local.slice(0, 2).join('')}${MASK_BULLET.repeat(bullets)}@${domain}`;
}

/** [text] with every address-looking token replaced by `[email]`, for an
 *  error message or log line that may quote a recipient (an SMTP rejection
 *  usually does) and must never carry one into the database or the logs. */
export function redactEmails(text: string): string {
  return String(text ?? '')
    .replace(/[^\s<>"'(),;:@]+@[\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)*/gu, '[email]');
}
