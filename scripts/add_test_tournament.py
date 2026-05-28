"""
One-time script: reads the user's Firebase JSON export, adds a
test-tournament-2026 node under Tournaments/, writes the modified
JSON to a new file alongside the original.

The original file is NEVER modified. The script is purely additive:
every other byte of the user's data passes through untouched.

Test tournament shape:
- 8 fake teams in 2 groups of 4
- 12 group-stage matches (all finished, with realistic scores)
- 2 semifinals (1 finished, 1 live)
- 1 third-place match (pending)
- 1 final (pending)
- 10 fake players per team = 80 total
- Dates: August 27-30, 2026 (a few months before the real
  September 4-7 national convention tournament)
"""

import json
import sys
from pathlib import Path

if len(sys.argv) < 2:
    print("Usage: python add_test_tournament.py <input.json> [output.json]")
    sys.exit(1)

input_path = Path(sys.argv[1])
output_path = (
    Path(sys.argv[2])
    if len(sys.argv) > 2
    else input_path.with_name(input_path.stem + "-with-test-tournament.json")
)


def make_team(team_id, name, group, seed, home, away):
    return {
        "AwayColor": away,
        "CityState": "Test City, TC",
        "CoachName": f"Coach {name.split()[1]}",
        "CoachPhotoUrl": "",
        "Established": "2024",
        "Group": group,
        "HomeColor": home,
        "LogoUrl": "",
        "Name": name,
        "Qualification": "Qualified",
        "Seed": seed,
    }


def make_table_row(gp, w, d, l, gs, gc):
    return {
        "D": d, "GC": gc, "GD": gs - gc, "GP": gp,
        "GS": gs, "L": l, "Pts": w * 3 + d, "W": w,
    }


def make_player(name, number, position, **stats):
    base = {
        "Assists": 0, "CleanSheets": 0, "DPL": 0, "Goals": 0,
        "Number": str(number), "Position": position,
        "RedCards": 0, "Saves": 0, "YellowCards": 0,
    }
    base.update(stats)
    return base


def make_match(match_id, stage, label, date, time, t1, t2, t1_score, t2_score,
               status, bracket_pos, location="Test Field A"):
    return {
        "BracketPosition": bracket_pos,
        "Date": date,
        "Label": label,
        "MatchLocation": location,
        "Stage": stage,
        "Status": status,
        "Team1Id": t1,
        "Team1Score": t1_score,
        "Team2Id": t2,
        "Team2Score": t2_score,
        "Time": time,
    }


# -----------------------------------------------------------------
# Teams
# -----------------------------------------------------------------
teams_data = {
    "test_eagles":   make_team("test_eagles",   "Test Eagles",   "Group A", 1, "#0066CC", "#FFFFFF"),
    "test_lions":    make_team("test_lions",    "Test Lions",    "Group A", 4, "#FFC107", "#000000"),
    "test_wolves":   make_team("test_wolves",   "Test Wolves",   "Group A", 5, "#607D8B", "#FFFFFF"),
    "test_bears":    make_team("test_bears",    "Test Bears",    "Group A", 8, "#5D4037", "#FFFFFF"),
    "test_sharks":   make_team("test_sharks",   "Test Sharks",   "Group B", 2, "#039BE5", "#FFFFFF"),
    "test_hawks":    make_team("test_hawks",    "Test Hawks",    "Group B", 3, "#D32F2F", "#FFFFFF"),
    "test_falcons":  make_team("test_falcons",  "Test Falcons",  "Group B", 6, "#388E3C", "#FFFFFF"),
    "test_panthers": make_team("test_panthers", "Test Panthers", "Group B", 7, "#212121", "#FF9800"),
}

# Group A standings: Eagles 1st (6pts), Lions 2nd (4pts), Wolves 3rd (3pts), Bears 4th (0pts)
# Group B standings: Sharks 1st (6pts), Hawks 2nd (4pts), Falcons 3rd (3pts), Panthers 4th (0pts)
table_data = {
    "test_eagles":   make_table_row(3, 2, 0, 1, 5, 3),
    "test_lions":    make_table_row(3, 1, 1, 1, 4, 4),
    "test_wolves":   make_table_row(3, 1, 0, 2, 3, 5),
    "test_bears":    make_table_row(3, 0, 1, 2, 2, 5),
    "test_sharks":   make_table_row(3, 2, 0, 1, 6, 3),
    "test_hawks":    make_table_row(3, 1, 1, 1, 4, 3),
    "test_falcons":  make_table_row(3, 1, 0, 2, 3, 4),
    "test_panthers": make_table_row(3, 0, 1, 2, 2, 5),
}

# -----------------------------------------------------------------
# Matches
# -----------------------------------------------------------------
matches_data = {}

# Group A — 6 matches across 3 days (08272026, 08282026, 08292026)
matches_data["gs_a_01"] = make_match("gs_a_01", "Group Stage", "Group A Match Day 1",
                                     "08272026", "10:00 AM",
                                     "test_eagles", "test_lions", 2, 1, 2, 1)
matches_data["gs_a_02"] = make_match("gs_a_02", "Group Stage", "Group A Match Day 1",
                                     "08272026", "12:00 PM",
                                     "test_wolves", "test_bears", 1, 1, 2, 2)
matches_data["gs_a_03"] = make_match("gs_a_03", "Group Stage", "Group A Match Day 2",
                                     "08282026", "10:00 AM",
                                     "test_eagles", "test_wolves", 2, 0, 2, 3)
matches_data["gs_a_04"] = make_match("gs_a_04", "Group Stage", "Group A Match Day 2",
                                     "08282026", "12:00 PM",
                                     "test_lions", "test_bears", 2, 0, 2, 4)
matches_data["gs_a_05"] = make_match("gs_a_05", "Group Stage", "Group A Match Day 3",
                                     "08292026", "10:00 AM",
                                     "test_eagles", "test_bears", 1, 2, 2, 5)
matches_data["gs_a_06"] = make_match("gs_a_06", "Group Stage", "Group A Match Day 3",
                                     "08292026", "12:00 PM",
                                     "test_lions", "test_wolves", 1, 2, 2, 6)

# Group B — 6 matches across 3 days
matches_data["gs_b_01"] = make_match("gs_b_01", "Group Stage", "Group B Match Day 1",
                                     "08272026", "2:00 PM",
                                     "test_sharks", "test_hawks", 2, 1, 2, 7,
                                     location="Test Field B")
matches_data["gs_b_02"] = make_match("gs_b_02", "Group Stage", "Group B Match Day 1",
                                     "08272026", "4:00 PM",
                                     "test_falcons", "test_panthers", 1, 1, 2, 8,
                                     location="Test Field B")
matches_data["gs_b_03"] = make_match("gs_b_03", "Group Stage", "Group B Match Day 2",
                                     "08282026", "2:00 PM",
                                     "test_sharks", "test_falcons", 3, 1, 2, 9,
                                     location="Test Field B")
matches_data["gs_b_04"] = make_match("gs_b_04", "Group Stage", "Group B Match Day 2",
                                     "08282026", "4:00 PM",
                                     "test_hawks", "test_panthers", 2, 0, 2, 10,
                                     location="Test Field B")
matches_data["gs_b_05"] = make_match("gs_b_05", "Group Stage", "Group B Match Day 3",
                                     "08292026", "2:00 PM",
                                     "test_sharks", "test_panthers", 1, 1, 2, 11,
                                     location="Test Field B")
matches_data["gs_b_06"] = make_match("gs_b_06", "Group Stage", "Group B Match Day 3",
                                     "08292026", "4:00 PM",
                                     "test_hawks", "test_falcons", 1, 1, 2, 12,
                                     location="Test Field B")

# Knockout — Aug 30
# SF1 (finished): Eagles (A1) vs Hawks (B2)
matches_data["sf_1"] = make_match("sf_1", "Semifinal", "Semifinal 1",
                                  "08302026", "10:00 AM",
                                  "test_eagles", "test_hawks", 2, 1, 2, 1)
# SF2 (live): Sharks (B1) vs Lions (A2) — in progress
matches_data["sf_2"] = make_match("sf_2", "Semifinal", "Semifinal 2",
                                  "08302026", "12:00 PM",
                                  "test_sharks", "test_lions", 1, 0, 1, 2)
# Third place (pending)
matches_data["third"] = make_match("third", "Third Place", "Third Place",
                                   "08302026", "2:00 PM",
                                   "test_hawks", "", 0, 0, 0, 1)
# Final (pending)
matches_data["final"] = make_match("final", "Final", "Final",
                                   "08302026", "4:00 PM",
                                   "test_eagles", "", 0, 0, 0, 1,
                                   location="Test Field A - Main")

# -----------------------------------------------------------------
# Rosters — 10 players per team
# -----------------------------------------------------------------
positions_seq = ["GK", "DEF", "DEF", "DEF", "MID", "MID", "MID", "FWD", "FWD", "FWD"]

# Realistic-ish but clearly fake first names
first_names = [
    "Alex", "Sam", "Chris", "Jordan", "Morgan", "Riley", "Casey", "Drew",
    "Quinn", "Avery", "Cameron", "Hayden", "Parker", "Skylar", "Reese",
]
last_names = [
    "Smith", "Johnson", "Williams", "Brown", "Davis", "Miller", "Wilson",
    "Moore", "Taylor", "Anderson", "Thomas", "Jackson", "White", "Harris",
    "Martin", "Thompson", "Garcia", "Martinez", "Robinson", "Clark",
]


def gen_roster(team_id, team_seed):
    """Generate 10 players for a team with simple stats spread."""
    roster = {}
    for i in range(10):
        first = first_names[(team_seed * 7 + i) % len(first_names)]
        last = last_names[(team_seed * 13 + i * 3) % len(last_names)]
        name = f"{first} {last}"
        # Avoid duplicates by adding initial
        if name in roster:
            name = f"{first} {last[0]}. {team_seed}{i}"
        pos = positions_seq[i]
        # Sprinkle some stats — top scorers in the tournament
        goals = 0
        assists = 0
        saves = 0
        clean_sheets = 0
        if pos == "GK":
            saves = 3 + (team_seed % 4)
            clean_sheets = 1 if team_seed <= 3 else 0
        elif pos == "FWD" and i == 7 and team_seed <= 2:
            goals = 4  # top scorer candidates: eagles_fwd0, sharks_fwd0
        elif pos == "FWD" and i == 8:
            goals = 2 if team_seed % 2 == 0 else 1
        elif pos == "MID" and i == 4 and team_seed <= 3:
            assists = 3
        elif pos == "MID":
            assists = 1 if i % 2 == 0 else 0
        roster[name] = make_player(
            name, i + 1, pos,
            Goals=goals, Assists=assists, Saves=saves, CleanSheets=clean_sheets,
        )
    return roster


team_seeds = {tid: t["Seed"] for tid, t in teams_data.items()}
rosters_data = {
    tid: gen_roster(tid, team_seeds[tid]) for tid in teams_data.keys()
}

# -----------------------------------------------------------------
# Test Tournament Header
# -----------------------------------------------------------------
test_tournament = {
    "Edition": "Test",
    "EndDate": "08302026",
    "Finished": False,
    "HostCity": "Test City, TC",
    "Location": "Test Sports Complex",
    "LogoUrl": "",
    "Matches": matches_data,
    "Name": "Test Tournament 2026",
    "Rosters": rosters_data,
    "Sport": "Soccer",
    "StartDate": "08272026",
    "Status": "Semifinals",
    "Table": table_data,
    "Teams": teams_data,
    # PredictionConfig — wired in for Phase 4 (predictions) testing
    "PredictionConfig": {
        "Open": True,
        "AwardsLockTime": "2026-08-27T10:00:00Z",
        "Scoring": {
            "Champion": 10,
            "RunnerUp": 5,
            "ThirdPlace": 3,
            "GoldenBoot": 8,
            "MostAssists": 8,
            "MostCleanSheets": 6,
            "BestDefender": 6,
            "MatchWinner": 1,
            "ExactScoreBonus": 3,
        },
        "Categories": {
            "Champion": True,
            "RunnerUp": True,
            "ThirdPlace": True,
            "GoldenBoot": True,
            "MostAssists": True,
            "MostCleanSheets": True,
            "BestDefender": True,
            "MatchWinner": True,
            "ExactScoreBonus": True,
        },
    },
}

# -----------------------------------------------------------------
# Load → merge → write
# -----------------------------------------------------------------
print(f"Reading {input_path}")
with open(input_path, "r", encoding="utf-8") as f:
    data = json.load(f)

original_top_keys = sorted(data.keys())
original_tournament_keys = sorted(data.get("Tournaments", {}).keys())

if "Tournaments" not in data:
    data["Tournaments"] = {}

if "test-tournament-2026" in data["Tournaments"]:
    print("WARNING: 'test-tournament-2026' already exists — it will be REPLACED.")

data["Tournaments"]["test-tournament-2026"] = test_tournament

# Sanity check — nothing else changed
new_top_keys = sorted(data.keys())
new_tournament_keys = sorted(data["Tournaments"].keys())
assert new_top_keys == original_top_keys, (
    f"Top-level keys changed! Before={original_top_keys} After={new_top_keys}"
)
expected_tournament_keys = sorted(set(original_tournament_keys) | {"test-tournament-2026"})
assert new_tournament_keys == expected_tournament_keys, (
    f"Tournament keys mismatch! Expected={expected_tournament_keys} Got={new_tournament_keys}"
)

print(f"Writing {output_path}")
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)

print()
print("DONE.")
print(f"  - Original file unchanged: {input_path}")
print(f"  - Modified file written:   {output_path}")
print(f"  - Top-level keys preserved: {len(original_top_keys)}")
print(f"  - Tournaments before: {len(original_tournament_keys)}, after: {len(new_tournament_keys)}")
print(f"  - Test tournament: {len(teams_data)} teams, {len(matches_data)} matches, "
      f"{sum(len(r) for r in rosters_data.values())} players")
