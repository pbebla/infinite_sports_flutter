// Admin login for the tools: an OAuth access token minted from the
// firebase-tools login (~/.config/configstore/firebase-tools.json), shared
// by fill_test_season.ts and merge_accounts.ts (moved here unchanged from
// fill_test_season.ts).
//
// The token rides in an `Authorization: Bearer` header — never in a URL.
// The token and the login file's contents are never printed, logged, or put
// in an error message.

import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

/* eslint-disable @typescript-eslint/no-explicit-any */

// The public firebase-tools "installed app" OAuth client (shipped in the
// firebase-tools source; not a secret) — what `firebase login` minted the
// refresh token for.
const OAUTH_CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const OAUTH_CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

let tokenOnce: Promise<string> | null = null;

/** One OAuth access token per run, minted on first use. */
export function accessToken(): Promise<string> {
  return (tokenOnce ??= mintAccessToken());
}

/** The firebase-tools refresh token. The login file holds secrets, so a
 *  read or parse failure is rethrown as a GENERIC message — never the
 *  underlying error, whose text can quote the file's contents (JSON.parse
 *  echoes the offending input). */
function readRefreshToken(file: string): unknown {
  let parsed: any;
  try {
    parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    throw new Error("Couldn't read the firebase-tools login file — run " +
      '`npx firebase-tools login` again.');
  }
  return parsed?.tokens?.refresh_token;
}

async function mintAccessToken(): Promise<string> {
  const file = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  if (!fs.existsSync(file)) {
    throw new Error('No firebase-tools login found — run `npx firebase-tools login` first.');
  }
  const refresh = readRefreshToken(file);
  if (typeof refresh !== 'string' || refresh.length === 0) {
    throw new Error('The firebase-tools login has no refresh token — run `npx firebase-tools login`.');
  }
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token', refresh_token: refresh,
      client_id: OAUTH_CLIENT_ID, client_secret: OAUTH_CLIENT_SECRET,
    }).toString(),
  });
  const json: any = await res.json().catch(() => null);
  if (!res.ok || typeof json?.access_token !== 'string') {
    throw new Error(`OAuth token exchange failed (HTTP ${res.status}${json?.error ? `, ${json.error}` : ''}).`);
  }
  return json.access_token;
}
