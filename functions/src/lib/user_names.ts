import type { Reference } from 'firebase-admin/database';

/** '{First Name} {Last Name}' from /Users/{uid}, 'Player' when absent. */
export async function readUserName(root: Reference, uid: string): Promise<string> {
  try {
    const [f, l] = await Promise.all([
      root.child(`Users/${uid}/First Name`).get(),
      root.child(`Users/${uid}/Last Name`).get(),
    ]);
    const name = `${f.val() ?? ''} ${l.val() ?? ''}`.trim();
    return name.length > 0 ? name : 'Player';
  } catch {
    return 'Player';
  }
}
