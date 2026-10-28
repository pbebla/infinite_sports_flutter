// Port of test/fantasy/stats_mapper_test.dart — coercion shapes,
// second-yellow counting, pen-save double-bump, attendance defaults.
import { describe, expect, it } from 'vitest';
import { mapGameToStats } from './stats_mapper';

// Mirrors a REAL `Futsal/<season>/Date/<MMDDYYYY>/<i>` node:
// - minute-keyed activity map with array buckets (team1activity),
//   one bucket index-Map-coerced (RTDB), `_t` insertion stamps on leaves;
// - team2activity arrives LIST-coerced (dense numeric minute keys) with a
//   leading null and one null leaf inside a bucket;
// - mixed score types (String '3' vs int 1) as utility.dart tolerates.
function gameNode(): Record<string, unknown> {
  return {
    team1: 'Sharks',
    team2: 'Wolves',
    team1score: '3',
    team2score: 1,
    status: 2,
    team1activity: {
      "5'": [
        { Goal: 'Alex', _t: 1111 },
        { Assist: 'Dana' },
      ],
      "12'": [
        { PenGoal: 'Alex' },
      ],
      "18'": {
        // bucket coerced to an index-keyed Map
        '0': { Save: 'Sam' },
        '1': { Save: 'Sam' },
      },
      "27'": [
        { PenSaved: 'Sam', _t: 2222 },
      ],
      "30'": [
        { Goal: 'Dana' },
        { Foul: 'Dana' }, // no fantasy counter — ignored
      ],
    },
    team2activity: [
      null, // RTDB null padding
      [
        { Yellow: 'Will' },
      ],
      [
        { Save: 'Wes' },
        { Goal: 'Wren' },
      ],
      [
        { SecondYellow: 'Will' },
        { PenMissed: 'Wren' },
        null, // null leaf inside a bucket
      ],
      [
        { DPL: 'Will' },
        { OwnGoal: 'Wes' },
        { Red: 'Wade' },
      ],
    ],
  };
}

describe('stats_mapper', () => {
  it('goals aggregate Goal + PenGoal; Foul has no fantasy counter', () => {
    const stats = mapGameToStats(gameNode(), { teamName: 'Sharks' });
    expect(stats['Alex'].goals).toBe(2); // Goal + PenGoal
    const dana = stats['Dana'];
    expect(dana.goals).toBe(1);
    expect(dana.assists).toBe(1);
    // Dana's Foul leaf changed nothing else.
    expect(dana.saves + dana.dpl + dana.yellows + dana.reds).toBe(0);
  });

  it('PenSaved credits the keeper on his OWN team list: penSaved AND a save',
    () => {
      // League pairing (statKeys ['PenSaved','Saves']): a penalty save is
      // also a save, so Sam = 2 Save events + 1 PenSaved = 3 saves.
      const stats = mapGameToStats(gameNode(), { teamName: 'Sharks' });
      expect(stats['Sam'].penSaved).toBe(1);
      expect(stats['Sam'].saves).toBe(3);
    });

  it('second yellow counts as a red, never a yellow; plain Red too', () => {
    const stats = mapGameToStats(gameNode(), { teamName: 'Wolves' });
    expect(stats['Will'].yellows).toBe(1); // the first Yellow only
    expect(stats['Will'].reds).toBe(1); // the SecondYellow IS the red
    expect(stats['Wade'].reds).toBe(1); // plain Red
  });

  it('teamConceded is the OPPOSING team final score, any score type', () => {
    const sharks = mapGameToStats(gameNode(), { teamName: 'Sharks' });
    const wolves = mapGameToStats(gameNode(), { teamName: 'Wolves' });
    expect(sharks['Alex'].teamConceded).toBe(1); // int score
    expect(wolves['Wren'].teamConceded).toBe(3); // String score '3'
  });

  it('List-coerced activity with leading null and null leaves parses', () => {
    const wolves = mapGameToStats(gameNode(), { teamName: 'Wolves' });
    expect(wolves['Wren'].goals).toBe(1);
    expect(wolves['Wren'].penMissed).toBe(1);
    expect(wolves['Wes'].saves).toBe(1);
    expect(wolves['Wes'].ownGoals).toBe(1);
    expect(wolves['Will'].dpl).toBe(1);
  });

  it('`_t` metadata keys on leaves are never read as event types', () => {
    const sharks = mapGameToStats(gameNode(), { teamName: 'Sharks' });
    // The '_t'-stamped leaves still land on the right counters...
    expect(sharks['Alex'].goals).toBe(2);
    expect(sharks['Sam'].penSaved).toBe(1);
    // ...and no phantom player named like an epoch stamp appears.
    expect(Object.keys(sharks).filter((k) => k.startsWith('_'))).toEqual([]);
    expect(Object.keys(sharks)).not.toContain('1111');
  });

  it('attendance null (absent node) means everyone present — spec §8', () => {
    const stats = mapGameToStats(gameNode(), { teamName: 'Sharks' });
    expect(Object.values(stats).every((s) => s.present)).toBe(true);
  });

  it('explicit attendance stamps through: absent player, zero-event player',
    () => {
      const stats = mapGameToStats(gameNode(), {
        teamName: 'Sharks',
        attendance: {
          Sam: true,
          Dana: true,
          Alex: false, // captured events but marked absent
          Riley: true, // zero activities, still present via attendance keys
        },
      });
      expect(stats['Alex'].present).toBe(false);
      expect(stats['Alex'].goals).toBe(2); // stats still tallied; scoring zeroes him
      const riley = stats['Riley'];
      expect(riley.present).toBe(true);
      expect(riley.goals).toBe(0);
      expect(riley.saves).toBe(0);
      expect(riley.teamConceded).toBe(1); // conceded stamps every roster entry
    });

  it('player with events but missing from attendance defaults to present',
    () => {
      const stats = mapGameToStats(gameNode(), {
        teamName: 'Sharks',
        attendance: { Sam: true }, // Dana/Alex not listed
      });
      expect(stats['Dana'].present).toBe(true);
    });

  it('a game with no activity yields only attendance players', () => {
    const node: Record<string, unknown> = {
      team1: 'Sharks',
      team2: 'Wolves',
      team1score: 0,
      team2score: 0,
      status: 0,
    };
    expect(mapGameToStats(node, { teamName: 'Sharks' })).toEqual({});
    const stats = mapGameToStats(node, {
      teamName: 'Sharks', attendance: { Sam: true, Riley: false },
    });
    expect(Object.keys(stats).sort()).toEqual(['Riley', 'Sam']);
    expect(stats['Sam'].present).toBe(true);
    expect(stats['Riley'].present).toBe(false);
    expect(stats['Sam'].teamConceded).toBe(0);
  });

  it('clean sheet source: conceded 0 when opponent never scored', () => {
    const node = gameNode();
    node['team2score'] = 0;
    const sharks = mapGameToStats(node, { teamName: 'Sharks' });
    expect(sharks['Sam'].teamConceded).toBe(0);
  });

  it('legacy score spelling team1Score/team2Score is read too', () => {
    const node = gameNode();
    delete node['team2score'];
    node['team2Score'] = 2;
    const sharks = mapGameToStats(node, { teamName: 'Sharks' });
    expect(sharks['Sam'].teamConceded).toBe(2);
  });

  it('unknown team name throws', () => {
    expect(() => mapGameToStats(gameNode(), { teamName: 'Eagles' })).toThrow();
  });
});
