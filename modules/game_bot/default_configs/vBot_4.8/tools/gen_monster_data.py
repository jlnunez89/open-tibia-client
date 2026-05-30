#!/usr/bin/env python3
"""Generate vBot/monster_data.lua from the decompiled 7.72 server mon/ files.

The client never ships the server-side MonsterRace files, so we bake the few
combat-relevant stats into a Lua table that the Monster Threat overlay script
loads at runtime. Only static facts are extracted (HP, experience, attack,
defense, armor, speed, damage immunities); a single composite "score" is
precomputed so the runtime can map monsters to danger tiers cheaply.

Immunities come from the monster Flags block (verified in crmain.cc: the only
damage immunities in 7.72 are NoPoison/NoBurning/NoEnergy/NoLifeDrain - there is
NO physical immunity, so melee always lands). NoParalyze is also captured
because it matters for kiting with paralyze runes.

Usage:
    python3 gen_monster_data.py [MON_DIR] [OUT_LUA]

Defaults assume the standard repo layout:
    MON_DIR = <repo>/decompiled-tibia-game/mon
    OUT_LUA = <this dir>/../vBot/monster_data.lua
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MON = os.path.normpath(
    os.path.join(HERE, "..", "..", "..", "..", "..", "..",
                 "decompiled-tibia-game", "mon"))
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, "..", "vBot", "monster_data.lua"))

# Skill tuples look like: (HitPoints, 8200, 0, 8200, 0, 0, 0)
_SKILL_RE = re.compile(r"\(\s*(\w+)\s*,\s*(-?\d+)")

# Damage-immunity flags -> single-letter codes stored in the `imm` string.
# p = poison/earth, f = fire, e = energy, d = death/life-drain.
_IMM_FLAGS = [("NoPoison", "p"), ("NoBurning", "f"),
             ("NoEnergy", "e"), ("NoLifeDrain", "d")]


def _has_flag(text, flag):
    # Flag tokens only ever appear inside the Flags={...} block, so a whole-word
    # search over the whole file is unambiguous.
    return re.search(rf"\b{flag}\b", text) is not None


def _scalar(text, key):
    m = re.search(rf"^{key}\s*=\s*(-?\d+)", text, re.MULTILINE)
    return int(m.group(1)) if m else 0


def _skill(text, key):
    for name, value in _SKILL_RE.findall(text):
        if name == key:
            return int(value)
    return 0


def parse(path):
    with open(path, "r", encoding="latin-1") as fh:
        text = fh.read()
    name_m = re.search(r'^Name\s*=\s*"([^"]*)"', text, re.MULTILINE)
    if not name_m:
        return None
    name = name_m.group(1).strip().lower()
    if not name:
        return None
    imm = "".join(code for flag, code in _IMM_FLAGS if _has_flag(text, flag))
    return {
        "name": name,
        "hp": _skill(text, "HitPoints"),
        "exp": _scalar(text, "Experience"),
        "atk": _scalar(text, "Attack"),
        "def": _scalar(text, "Defend"),
        "arm": _scalar(text, "Armor"),
        "spd": _skill(text, "GoStrength"),
        "imm": imm,
        "para": 0 if _has_flag(text, "NoParalyze") else 1,
    }


def score(m):
    # Weighted danger proxy. Attack drives per-hit pain, HP drives time-to-kill,
    # experience captures "overall toughness" (spells, regen, etc. we don't model).
    return round(m["atk"] * 10 + m["hp"] * 0.25 + m["exp"] * 0.5)


def main():
    mon_dir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MON
    out_lua = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT

    monsters = []
    for fname in sorted(os.listdir(mon_dir)):
        if not fname.endswith(".mon"):
            continue
        data = parse(os.path.join(mon_dir, fname))
        if data:
            data["score"] = score(data)
            monsters.append(data)

    lines = [
        "-- AUTO-GENERATED from decompiled-tibia-game/mon/*.mon - do not edit by hand.",
        "-- Regenerate with: tools/gen_monster_data.py",
        "-- Fields: hp, exp, atk (attack), def (defense), arm (armor), spd (speed),",
        "--         score (precomputed danger proxy, see gen_monster_data.py),",
        "--         imm (immune damage: p=poison/earth f=fire e=energy d=death),",
        "--         para (1 = can be paralyzed, 0 = paralyze-immune).",
        "--         Actual move speed = spd*2+80 (compare to player:getSpeed()).",
        "MonsterData = {",
    ]
    for m in monsters:
        lines.append(
            '  ["%s"] = {hp=%d, exp=%d, atk=%d, def=%d, arm=%d, spd=%d, score=%d, imm="%s", para=%d},'
            % (m["name"], m["hp"], m["exp"], m["atk"], m["def"], m["arm"],
               m["spd"], m["score"], m["imm"], m["para"]))
    lines.append("}")
    lines.append("")

    with open(out_lua, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))

    scores = sorted(m["score"] for m in monsters)
    print("Wrote %d monsters -> %s" % (len(monsters), out_lua))
    if scores:
        n = len(scores)
        pct = lambda p: scores[min(n - 1, int(n * p))]
        print("score min/p25/median/p75/p90/max: %d / %d / %d / %d / %d / %d"
              % (scores[0], pct(.25), pct(.5), pct(.75), pct(.9), scores[-1]))


if __name__ == "__main__":
    main()
