"""Sharing recorded data: your export (opt-in) and merging everyone's shares into the community data.

Since 2.5 the addon writes the same numbers itself (Share.lua, off until the player switches it on) with Finds.lua's in
"fx"; tools/community/build_data.py turns the merged result into the addon's CommunityData.lua.

export_share(db) writes share\\sunstone-share-<date>.json with numbers only: quest XP and gold, creature
kills / coins / drops / skinning / reputation per kill, vendor sell prices, what vendors charge (gold, Honor,
Merchant's Favor, marks), timed battlegrounds (minutes, Honor, Rank Points, marks per match) and the kill-XP
calibration. No character names, realms, GUIDs or any text, so nothing in it can identify you or carry a
message to anyone's AI.

Since 1.6 a share also has the group side of each creature (kills made in a group: shared loot and coins,
split XP), the recorder's clock per kind of play (solo / group / dungeon / raid, per level) and timed
dungeon runs (by the dungeon's number, not its name).

import_friend(path) takes a friend's Sunstone.lua (their SavedVariables, sent over Discord or the like):
it is READ, never run (a plain parser for the saved-data format), cleaned exactly like a share (numbers
only, so their character names, gear, bags and gold are thrown away) and kept in share\\friends\\. A
friend sending a newer file replaces their older one. merge_friends() pools those into data\\friends.json
with min_reports=1 (they're people you know; the troll limits still apply).

merge(shares) is what the maintainer runs over everyone's shares before a release; it writes
data\\community.json, which every copy of the helper reads. To keep one person (or a troll) from
steering the numbers:
  * every share is checked: only known fields, only numbers, every value inside sane limits;
  * one share counts at most CAP_KILLS kills per creature (bigger ones are scaled down);
  * a creature or quest is only used when at least `min_reports` separate shares report it;
  * shares whose coins-per-corpse or kill XP are far off everyone else's (3x the median) are dropped.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import statistics
import time

FORMAT = 1
CAP_KILLS = 500
CAP_MATCHES = 100  # battleground matches one share can count for
LIMITS = {"k": 100000, "l": 100000, "xk": 100000, "sn": 100000}
STYLE_KINDS = ("solo", "group", "dungeon", "raid")
MAX_SHARE_RUNS = 150
MAX_FRIEND_FILE = 64 * 1024 * 1024  # bytes: a SavedVariables file far bigger than this isn't one


def _int(v, lo, hi):
    if isinstance(v, bool) or not isinstance(v, (int, float)) or v != v:
        return None
    v = int(v)
    return v if lo <= v <= hi else None


def _num(v, lo, hi):
    if isinstance(v, bool) or not isinstance(v, (int, float)) or v != v:
        return None
    v = float(v)
    return v if lo <= v <= hi else None


def _id(k):
    try:
        k = int(k)
    except (TypeError, ValueError):
        return None
    return k if 0 < k < 10_000_000 else None


def _pairs(obj):
    """(key, value) pairs of a saved table, which comes back as a list when its keys are 1..n."""
    if isinstance(obj, list):
        return list(enumerate(obj, 1))
    if isinstance(obj, dict):
        return list(obj.items())
    return []


def clean_vend(vend) -> dict:
    """What vendors charge, as the addon's vendor recorder saw it: {npc: {"r": standing, "i": {item: {"c": copper,
    "n": items per purchase, "x": [[kind 1 currency / 2 item, id, amount], ...]}}}}. Anything else is dropped."""
    out = {}
    if not isinstance(vend, dict):
        return out
    for k, v in list(vend.items())[:300]:
        npc = _id(k)
        if npc is None or not isinstance(v, dict) or not isinstance(v.get("i"), dict):
            continue
        items = {}
        for ik, e in list(v["i"].items())[:150]:
            iid = _id(ik)
            if iid is None or not isinstance(e, dict):
                continue
            c = _int(e.get("c") or 0, 0, 50_000_000)
            n = _int(e.get("n") or 1, 1, 1000)
            parts = []
            for x in (e.get("x") or [])[:3] if isinstance(e.get("x"), list) else []:
                if isinstance(x, list) and len(x) == 3:
                    kind, cid, amt = _int(x[0], 1, 2), _id(x[1]), _int(x[2], 1, 1_000_000)
                    if kind is not None and cid is not None and amt is not None:
                        parts.append([kind, cid, amt])
            if c is None or n is None or (not c and not parts):
                continue
            items[iid] = {"c": c, "n": n, **({"x": parts} if parts else {})}
        if items:
            r = _int(v.get("r"), 1, 8)
            out[npc] = {"i": items, **({"r": r} if r is not None else {})}
    return out


PVP_FIELDS = {"n": (0, 100000), "hn": (0, 100000), "rn": (0, 100000), "wn": (0, 100000), "w": (0, 100000)}


def clean_pvp(pvp) -> dict:
    """Timed battlegrounds: {map: {n matches, m minutes, h Honor, hn, rp Rank Points, rn, mk marks, w wins, wn}},
    each total within what that many matches could give."""
    out = {}
    if not isinstance(pvp, dict):
        return out
    for k, e in list(pvp.items())[:20]:
        try:
            mid = int(k)
        except (TypeError, ValueError):
            continue
        if not 0 <= mid <= 100000 or isinstance(k, bool) or not isinstance(e, dict):
            continue
        t = {f: _int(e.get(f) or 0, lo, hi) for f, (lo, hi) in PVP_FIELDS.items()}
        if any(v is None for v in t.values()) or not t["n"] or t["hn"] > t["n"] or t["rn"] > t["n"] or t["wn"] > t["n"] \
                or t["w"] > t["wn"]:
            continue
        m = _num(e.get("m") or 0, 2 * t["n"], 120 * t["n"])
        h = _num(e.get("h") or 0, 0, 5000 * max(t["hn"], 1))
        rp = _num(e.get("rp") or 0, 0, 2000 * max(t["rn"], 1))
        mk = _num(e.get("mk") or 0, 0, 10 * t["n"])
        if None in (m, h, rp, mk):
            continue
        out[mid] = dict(t, m=m, h=h, rp=rp, mk=mk)
    return out


def _clean_mob(v, rep=True) -> dict | None:
    """One creature's numbers (its solo side, or with rep=False its group side), or None when there's nothing."""
    if not isinstance(v, dict):
        return None
    m = {}
    for f, hi in LIMITS.items():
        m[f] = _int(v.get(f) or 0, 0, hi) or 0
    if m["k"] == 0 and m["l"] == 0 and m["sn"] == 0:
        return None
    loots = max(m["l"], 1)
    m["c"] = _num(v.get("c") or 0, 0, loots * 500000) or 0.0        # at most 50 gold coins per corpse
    m["v"] = _num(v.get("v") or 0, 0, loots * 2_000_000) or 0.0     # vendor value of the drops
    m["x"] = _num(v.get("x") or 0, 0, max(m["xk"], 1) * 20000) or 0.0
    m["rv"] = _num(v.get("rv") or 0, 0, loots * 5_000_000) or 0.0  # vendor value of random green/blue drops
    ty = _int(v.get("ty"), 1, 15)
    if ty is not None:
        m["ty"] = ty
    for f, cap in (("i", m["l"]), ("r", m["l"]), ("sk", m["sn"])):
        items = {}
        for iid, n in _pairs(v.get(f))[:40]:
            i, n = _id(iid), _int(n, 1, max(cap, 1) * 20)
            if i is not None and n is not None:
                items[i] = n
        m[f] = items
    for f in ("lo", "hi"):
        lv = _int(v.get(f), 1, 63)
        if lv is not None:
            m[f] = lv
    if not rep:
        return m
    reps = {}  # reputation per kill: {faction: {"g": reputation, "n": kills that gave it}}
    for fk, e in list((v.get("f") or {}).items())[:8] if isinstance(v.get("f"), dict) else []:
        fid = _id(fk)
        if fid is None or not isinstance(e, dict):
            continue
        n = _int(e.get("n"), 1, max(m["k"], 1))
        g = _num(e.get("g"), 0, (n or 0) * 2000) if n else None
        if n and g:
            reps[fid] = {"g": g, "n": n}
    if reps:
        m["f"] = reps
    return m


EMPTY_MOB = {"k": 0, "l": 0, "xk": 0, "sn": 0, "c": 0.0, "v": 0.0, "x": 0.0, "rv": 0.0, "i": {}, "r": {}, "sk": {}}


def _clean_ctx(ctx) -> dict:
    """The recorder's clock per kind of play and level: {kind: {level: {t, k, l, c, x, xr, v, rv, gv, i}}}.
    A level whose numbers couldn't come from that much play is dropped whole."""
    out = {}
    if not isinstance(ctx, dict):
        return out
    for kind in STYLE_KINDS:
        levels = {}
        for lk, b in _pairs(ctx.get(kind))[:70]:
            lv = _id(lk)  # a number, or a number written as text (JSON keys)
            if lv is None or lv > 63 or not isinstance(b, dict):
                continue
            t = _num(b.get("t") or 0, 60, 3600 * 24 * 90)
            k, l = _int(b.get("k") or 0, 0, 1_000_000), _int(b.get("l") or 0, 0, 1_000_000)
            if None in (t, k, l):
                continue
            h = t / 3600
            e = {"t": t, "k": k, "l": l}
            caps = {"c": max(l, 1) * 500000 + h * 2_000_000, "x": h * 3_000_000 + 1000, "v": max(l, 1) * 2_000_000,
                    "rv": max(l, 1) * 5_000_000, "gv": h * 5_000_000 + 1000}
            for f, cap in caps.items():
                e[f] = _num(b.get(f) or 0, 0, cap)
            if None in e.values():
                continue
            e["xr"] = _num(b.get("xr") or 0, 0, e["x"]) or 0.0
            items = {}
            for iid, n in _pairs(b.get("i"))[:80]:
                i, n = _id(iid), _int(n, 1, (k + l + 1) * 20)
                if i is not None and n is not None:
                    items[i] = n
            e["i"] = items
            levels[lv] = e
        if levels:
            out[kind] = levels
    return out


def _clean_runs(runs) -> list:
    """Timed dungeon / raid runs, by the dungeon's number only: [{id, t seconds, lvl, n group size, k, l, c, x, v, i}]."""
    out = []
    for _, r in _pairs(runs)[-MAX_SHARE_RUNS:]:
        if not isinstance(r, dict):
            continue
        rid, t = _int(r.get("id"), 1, 100000), _int(r.get("t"), 180, 6 * 3600)
        lvl, n = _int(r.get("lvl"), 1, 63), _int(r.get("n") or 1, 1, 40)
        k, l = _int(r.get("k") or 0, 0, 5000), _int(r.get("l") or 0, 0, 5000)
        if None in (rid, t, lvl, n, k, l):
            continue
        c = _num(r.get("c") or 0, 0, max(l, 1) * 500000 + t / 3600 * 2_000_000)
        x = _num(r.get("x") or 0, 0, t / 3600 * 3_000_000 + 1000)
        v = _num(r.get("v") or 0, 0, max(l, 1) * 2_000_000)
        if None in (c, x, v):
            continue
        items = {}
        for iid, cnt in _pairs(r.get("i"))[:80]:
            i, cnt = _id(iid), _int(cnt, 1, (l + 1) * 20)
            if i is not None and cnt is not None:
                items[i] = cnt
        out.append({"id": rid, "t": t, "lvl": lvl, "n": n, "k": k, "l": l, "c": c, "x": x, "v": v, "i": items})
    return out


CLASSES = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"}
NAME = re.compile(r"^[A-Za-z][A-Za-z '\-,]{1,39}$")


def _cell(k):
    """A spot: map * 10000 + x in hundredths * 100 + y in hundredths."""
    try:
        k = int(k)
    except (TypeError, ValueError):
        return None
    return k if 900 * 10000 <= k < 4000 * 10000 else None


def _clean_cells(t, cap) -> dict:
    out = {}
    for k, n in _pairs(t)[:10]:
        c, n = _cell(k), _int(n, 1, cap)
        if c is not None and n is not None:
            out[c] = n
    return out


def clean_fx(fx) -> dict:
    """What Finds.lua recorded (since 2.5): spots creatures were fought at, what chests / opened items / fishing gave, quest
    rewards, XP and fight times by level, sources of pets and mounts, names of creatures nobody knew."""
    out = {"at": {}, "obj": {}, "box": {}, "fish": {}, "qi": {}, "nm": {}, "xp": {}, "kt": {}, "news": []}
    if not isinstance(fx, dict):
        return out
    for k, t in _pairs(fx.get("at"))[:3000]:
        npc, c = _id(k), _clean_cells(t, 100000)
        if npc is not None and c:
            out["at"][npc] = c
    for kind, most in (("obj", 800), ("box", 300), ("fish", 120)):
        for k, e in _pairs(fx.get(kind))[:most]:
            i = _id(k)
            n = _int(e.get("n"), 1, 100000) if isinstance(e, dict) else None
            if i is None or n is None:
                continue
            items = {}
            for iid, c in _pairs(e.get("i"))[:60]:
                iid, c = _id(iid), _int(c, 1, n * 40)
                if iid is not None and c is not None:
                    items[iid] = c
            o = {"n": n, "i": items}
            at = _clean_cells(e.get("at"), 100000) if kind == "obj" else None
            if at:
                o["at"] = at
            out[kind][i] = o
    for k, items in _pairs(fx.get("qi"))[:3000]:
        q = _id(k)
        ids = [i for i in (_id(x) for x in (items if isinstance(items, list) else [])[:12]) if i is not None]
        if q is not None and ids:
            out["qi"][q] = ids
    for k, name in _pairs(fx.get("nm"))[:400]:
        npc = _id(k)
        if npc is not None and isinstance(name, str) and NAME.match(name):
            out["nm"][npc] = name

    def table(t, lo, hi):
        o = {}
        for lk, row in _pairs(t)[:63]:
            lv = _id(lk)
            if lv is None or lv > 60:
                continue
            for dk, e in _pairs(row)[:60]:
                try:
                    d = int(dk)
                except (TypeError, ValueError):
                    continue
                base = d - 100 if d >= 60 else d
                if not -20 <= base <= 8 or not isinstance(e, list) or len(e) != 2:
                    continue
                n = _int(e[0], 1, 100000)
                v = _num(e[1], n * lo, n * hi) if n else None
                if v is not None:
                    o.setdefault(lv, {})[d] = [n, v]
        return o
    out["xp"] = table(fx.get("xp"), 1, 20000)
    for cls, t in list(fx.get("kt").items())[:9] if isinstance(fx.get("kt"), dict) else []:
        if cls in CLASSES:
            o = table(t, 1, 180)
            if o:
                out["kt"][cls] = o
    for e in (fx.get("news") if isinstance(fx.get("news"), list) else [])[:200]:
        if isinstance(e, dict):
            i, k, sid, n = _id(e.get("i")), _int(e.get("k"), 1, 6), _id(e.get("s")), _int(e.get("n") or 1, 1, 10000)
            if None not in (i, k, sid, n):
                out["news"].append({"i": i, "k": k, "s": sid, "n": n})
    return out


def merge_fx(shares, min_reports: int = 3) -> dict:
    """Everyone's finds pooled, each entry with how many players it's from (`p`). What counts as enough is decided where
    it's used (a pet's source shows from one report, as not confirmed; chances need several)."""
    out = {"at": {}, "obj": {}, "box": {}, "fish": {}, "qi": {}, "nm": {}, "xp": {}, "kt": {}, "src": {}}
    fxs = [s["fx"] for s in shares]
    spots: dict = {}
    for f in fxs:
        for npc, cells in f["at"].items():
            for c, n in cells.items():
                e = spots.setdefault(npc, {}).setdefault(c, [0, 0])
                e[0] += 1
                e[1] += min(n, 20)
    for npc, cells in spots.items():
        best = sorted(cells.items(), key=lambda x: (-x[1][0], -x[1][1]))[:12]
        out["at"][npc] = {"p": max(c[0] for _, c in best), "c": [k for k, _ in best]}
    for kind in ("obj", "box", "fish"):
        by: dict = {}
        for f in fxs:
            for i, e in f[kind].items():
                by.setdefault(i, []).append(e)
        for i, es in by.items():
            if len(es) < min(min_reports, 2):
                continue
            t = {"p": len(es), "n": 0, "i": {}}
            at: dict = {}
            for e in es:
                sc = min(1.0, 200 / e["n"])
                t["n"] += max(1, int(round(e["n"] * sc)))
                for iid, n in e["i"].items():
                    t["i"][iid] = t["i"].get(iid, 0) + n * sc
                for c in (e.get("at") or {}):
                    at[c] = at.get(c, 0) + 1
            t["i"] = {iid: round(n, 1) for iid, n in t["i"].items() if n >= 0.5}
            if at:
                t["at"] = sorted(at, key=lambda c: -at[c])[:12]
            out[kind][i] = t
    names: dict = {}
    for f in fxs:
        for npc, name in f["nm"].items():
            names.setdefault(npc, []).append(name)
    for npc, ns in names.items():  # a name only when at least two players saw the very same one
        best = max(set(ns), key=ns.count)
        if ns.count(best) >= 2:
            out["nm"][npc] = best
    rew: dict = {}
    for f in fxs:
        for q, ids in f["qi"].items():
            rew.setdefault(q, []).append(tuple(ids))
    for q, ls in rew.items():
        best = max(set(ls), key=ls.count)
        if ls.count(best) >= min(min_reports, 2):
            out["qi"][q] = list(best)

    def pool(tables):
        by: dict = {}
        for t in tables:
            for lv, row in t.items():
                for d, (n, v) in row.items():
                    by.setdefault((lv, d), []).append((n, v))
        o: dict = {}
        for (lv, d), es in by.items():
            es = _drop_outliers(es, lambda e: e[1] / e[0])
            if len(es) >= min(min_reports, 2):
                n = sum(min(a, 200) for a, _ in es)
                o.setdefault(lv, {})[d] = [n, round(sum(min(a, 200) * (v / a) for a, v in es) / n, 2)]
        return o
    out["xp"] = pool([f["xp"] for f in fxs])
    for cls in sorted(CLASSES):
        t = pool([f["kt"][cls] for f in fxs if cls in f["kt"]])
        if t:
            out["kt"][cls] = t
    src: dict = {}
    for s in shares:
        for e in s["fx"]["news"]:
            x = src.setdefault(e["i"], {}).setdefault((e["k"], e["s"]), [0, 0])
            x[0] += 1
            x[1] += min(e["n"], 20)
    for item, es in src.items():
        rows = []
        for (k, sid), (p, n) in es.items():
            of = 0
            if k == 1:
                of = sum(s["mobs"][sid]["l"] + (s["mobs"][sid].get("g") or {}).get("l", 0) for s in shares if sid in s["mobs"])
            elif k in (2, 3, 4):
                of = out[{2: "obj", 3: "box", 4: "fish"}[k]].get(sid, {}).get("n", 0)
            rows.append([k, sid, p, n, max(of, n) if of else 0])
        out["src"][item] = sorted(rows, key=lambda r: -r[2])[:8]
    return out


def clean_share(data) -> dict:
    """Only the fields we know, only numbers within limits; anything else is dropped."""
    out = {"format": FORMAT, "quests": {}, "mobs": {}, "sell": {}, "cal": {"f": 0.0, "x": 0.0, "n": 0}}
    if not isinstance(data, dict):
        return out
    for k, v in _pairs(data.get("quests")):
        qid = _id(k)
        if qid is None or not isinstance(v, dict):
            continue
        x, m, l = _int(v.get("x"), 0, 200000), _int(v.get("m"), 0, 2_000_000), _int(v.get("l"), 1, 60)
        if x is not None and m is not None and l is not None:
            out["quests"][qid] = {"x": x, "m": m, "l": l}
    for k, v in _pairs(data.get("mobs")):
        npc = _id(k)
        if npc is None or not isinstance(v, dict):
            continue
        m = _clean_mob(v)
        g = _clean_mob(v.get("g"), rep=False)  # kills made in a group
        if g:
            m = m or json.loads(json.dumps(EMPTY_MOB))
            m["g"] = g
        if m:
            out["mobs"][npc] = m
    for k, v in _pairs(data.get("sell")):
        i, p = _id(k), _int(v, 0, 50_000_000)
        if i is not None and p is not None:
            out["sell"][i] = p
    out["qual"] = {}
    for k, v in _pairs(data.get("qual")):
        i, qv = _id(k), _int(v, 0, 7)
        if i is not None and qv is not None:
            out["qual"][i] = qv
    cal = data.get("cal") or {}
    f, x, n = _num(cal.get("f") or 0, 0, 1e9), _num(cal.get("x") or 0, 0, 1e9), _int(cal.get("n") or 0, 0, 1_000_000)
    if f and x is not None and n and 0.3 <= x / f <= 3.0:
        out["cal"] = {"f": f, "x": x, "n": n}
    out["vend"] = clean_vend(data.get("vend"))
    out["pvp"] = clean_pvp(data.get("pvp"))
    out["ctx"] = _clean_ctx(data.get("ctx"))
    out["runs"] = _clean_runs(data.get("runs"))
    out["fx"] = clean_fx(data.get("fx"))
    return out


def _rec_fields(rec: dict) -> dict:
    return {f: rec.get(f) for f in ("quests", "mobs", "sell", "cal", "qual", "vend", "pvp", "ctx", "runs", "fx")}


def summarize(data: dict) -> dict:
    mobs = data.get("mobs") or {}
    return {"quests": len(data.get("quests") or {}), "creatures": len(mobs),
            "kills": sum(m["k"] + (m.get("g") or {}).get("k", 0) for m in mobs.values()),
            "corpses": sum(m["l"] + (m.get("g") or {}).get("l", 0) for m in mobs.values()),
            "group_kills": sum((m.get("g") or {}).get("k", 0) for m in mobs.values()),
            "vendors": len(data.get("vend") or {}), "matches": sum(e["n"] for e in (data.get("pvp") or {}).values()),
            "runs": len(data.get("runs") or []),
            "hours": {k: round(sum(b["t"] for b in lv.values()) / 3600, 1) for k, lv in (data.get("ctx") or {}).items()}}


def export_share(db: dict | None, folder: str) -> tuple[str, dict]:
    """Write your recorded numbers to a file you can choose to send. Returns (path, summary)."""
    rec = (db or {}).get("rec") or {}
    data = clean_share(_rec_fields(rec))
    data["made"] = time.strftime("%Y-%m-%d")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"sunstone-share-{time.strftime('%Y%m%d-%H%M')}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"))
    return path, summarize(data)


def _drop_outliers(entries, key):
    vals = [key(e) for e in entries if key(e) is not None]
    if len(vals) < 3:
        return entries
    med = statistics.median(vals)
    if med <= 0:
        return entries
    return [e for e in entries if key(e) is None or med / 3 <= key(e) <= med * 3]


def _pool_mob(entries, min_reports):
    """Several shares' numbers for one creature (one side) -> the pooled numbers, or None."""
    if len(entries) < min_reports:
        return None
    entries = _drop_outliers(entries, lambda e: (e[0]["c"] / e[0]["l"]) if e[0]["l"] >= 5 else None)
    entries = _drop_outliers(entries, lambda e: (e[0]["x"] / e[0]["xk"]) if e[0]["xk"] >= 5 else None)
    if len(entries) < min_reports:
        return None
    t = {"k": 0, "l": 0, "c": 0.0, "v": 0.0, "rv": 0.0, "x": 0.0, "xk": 0, "sn": 0, "i": {}, "r": {}, "sk": {}}
    for m, sc in entries:
        for f in ("k", "l", "xk", "sn"):
            t[f] += int(round(m[f] * sc))
        for f in ("c", "v", "rv", "x"):
            t[f] += m.get(f, 0.0) * sc
        if m.get("ty") and not t.get("ty"):
            t["ty"] = m["ty"]
        for f in ("i", "r", "sk"):
            for i, n in m[f].items():
                t[f][i] = t[f].get(i, 0) + int(round(n * sc))
        for f in ("lo", "hi"):
            if f in m:
                t[f] = min(t.get(f, m[f]), m[f]) if f == "lo" else max(t.get(f, m[f]), m[f])
        for fid, e in (m.get("f") or {}).items():  # reputation per kill
            ft = t.setdefault("f", {}).setdefault(fid, {"g": 0.0, "n": 0})
            ft["g"] += e["g"] * sc
            ft["n"] += int(round(e["n"] * sc))
    t["reports"] = len(entries)
    return t


def merge(shares: list[dict], min_reports: int = 3) -> dict:
    """Everyone's shares -> the community data (see the module notes for the rules)."""
    shares = [clean_share(s) for s in shares]
    out = {"format": FORMAT, "built": time.strftime("%Y-%m-%d"), "shares": len(shares), "quests": {}, "mobs": {}, "sell": {},
           "cal": {"f": 0.0, "x": 0.0, "n": 0}}
    # creatures: solo sides and group sides pooled apart (group coins are shares, group XP is split)
    for side in ("solo", "group"):
        by_mob: dict[int, list] = {}
        for s in shares:
            for npc, m in s["mobs"].items():
                m = m if side == "solo" else m.get("g")
                if not m or (m["k"] == 0 and m["l"] == 0 and m["sn"] == 0):
                    continue
                scale = min(1.0, CAP_KILLS / max(m["k"], m["l"], 1))
                by_mob.setdefault(npc, []).append((m, scale))
        for npc, entries in by_mob.items():
            t = _pool_mob(entries, min_reports)
            if t is None:
                continue
            if side == "solo":
                out["mobs"][npc] = t
            else:
                out["mobs"].setdefault(npc, dict(json.loads(json.dumps(EMPTY_MOB)), reports=0))["g"] = t
    # quests: the median gold reward (gold is fixed per quest below max level)
    by_q: dict[int, list] = {}
    for s in shares:
        for qid, q in s["quests"].items():
            if q["l"] < 60:
                by_q.setdefault(qid, []).append(q)
    for qid, qs in by_q.items():
        if len(qs) >= min_reports:
            out["quests"][qid] = {"x": int(statistics.median(q["x"] for q in qs)), "m": int(statistics.median(q["m"] for q in qs)),
                                  "l": int(statistics.median(q["l"] for q in qs)), "reports": len(qs)}
    # vendor prices: the median of everyone who saw the item
    by_i: dict[int, list] = {}
    for s in shares:
        for i, p in s["sell"].items():
            by_i.setdefault(i, []).append(p)
    for i, ps in by_i.items():
        if len(ps) >= min(min_reports, 2):
            out["sell"][i] = int(statistics.median(ps))
    # item quality: what most shares say
    by_q2: dict[int, list] = {}
    for s_ in shares:
        for i, qv in s_["qual"].items():
            by_q2.setdefault(i, []).append(qv)
    out["qual"] = {i: max(set(v), key=v.count) for i, v in by_q2.items()}
    # kill-XP calibration
    for s in shares:
        c = s["cal"]
        if c["n"]:
            sc = min(1.0, CAP_KILLS / c["n"])
            out["cal"]["f"] += c["f"] * sc
            out["cal"]["x"] += c["x"] * sc
            out["cal"]["n"] += int(round(c["n"] * sc))
    # what vendors charge: prices are fixed, so the price most shares agree on (seen by at least 2)
    by_v: dict[tuple, list] = {}
    for s in shares:
        for npc, v in s["vend"].items():
            for iid, e in v["i"].items():
                by_v.setdefault((npc, iid), []).append(json.dumps(e, sort_keys=True))
    out["vend"] = {}
    for (npc, iid), seen in by_v.items():
        best = max(set(seen), key=seen.count)
        if seen.count(best) >= min(min_reports, 2):
            out["vend"].setdefault(npc, {"i": {}})["i"][iid] = json.loads(best)
    # timed battlegrounds: at most CAP_MATCHES matches per share, shares far off everyone's Honor per match dropped
    by_bg: dict[int, list] = {}
    for s in shares:
        for mid, e in s["pvp"].items():
            by_bg.setdefault(mid, []).append(e)
    out["pvp"] = {}
    for mid, entries in by_bg.items():
        if len(entries) < min_reports:
            continue
        entries = _drop_outliers(entries, lambda e: (e["h"] / e["hn"]) if e["hn"] >= 3 else None)
        if len(entries) < min_reports:
            continue
        t = {"n": 0, "m": 0.0, "h": 0.0, "hn": 0, "rp": 0.0, "rn": 0, "mk": 0.0, "w": 0, "wn": 0}
        for e in entries:
            sc = min(1.0, CAP_MATCHES / max(e["n"], 1))
            for f in t:
                t[f] += e[f] * sc
        for f in ("n", "hn", "rn", "w", "wn"):
            t[f] = int(round(t[f]))
        t["reports"] = len(entries)
        out["pvp"][mid] = t
    # how people play: the recorder's clock summed per kind and level, and everyone's runs (newest kept)
    ctx = {}
    for s in shares:
        for kind, levels in s["ctx"].items():
            for lv, b in levels.items():
                e = ctx.setdefault(kind, {}).setdefault(lv, {"t": 0.0, "k": 0, "l": 0, "c": 0.0, "x": 0.0, "xr": 0.0,
                                                               "v": 0.0, "rv": 0.0, "gv": 0.0, "i": {}})
                for f in ("t", "k", "l", "c", "x", "xr", "v", "rv", "gv"):
                    e[f] += b.get(f, 0)
                for i, n in b["i"].items():
                    e["i"][i] = e["i"].get(i, 0) + n
    out["ctx"] = ctx
    out["runs"] = [r for s in shares for r in s["runs"]][-1000:]
    out["fx"] = merge_fx(shares, min_reports)
    return out


def combine(a: dict | None, b: dict | None) -> dict:
    """Two pooled data sets (the community's and your friends') added together. Keys may be strings (from JSON)."""
    if not a:
        return b or {}
    if not b:
        return a
    out = json.loads(json.dumps(a))

    def add_mob(t, m):
        for f in ("k", "l", "xk", "sn", "c", "v", "rv", "x"):
            t[f] = t.get(f, 0) + (m.get(f) or 0)
        for f in ("i", "r", "sk"):
            d = t.setdefault(f, {})
            for i, n in (m.get(f) or {}).items():
                d[i] = d.get(i, 0) + n
        for fid, e in (m.get("f") or {}).items():
            ft = t.setdefault("f", {}).setdefault(fid, {"g": 0.0, "n": 0})
            ft["g"] += e.get("g", 0)
            ft["n"] += e.get("n", 0)
        if m.get("ty") and not t.get("ty"):
            t["ty"] = m["ty"]
        for f in ("lo", "hi"):
            if isinstance(m.get(f), int):
                t[f] = (min if f == "lo" else max)(t.get(f, m[f]), m[f])
        if isinstance(m.get("g"), dict):
            add_mob(t.setdefault("g", {}), m["g"])

    for npc, m in (b.get("mobs") or {}).items():
        if npc in out.setdefault("mobs", {}):
            add_mob(out["mobs"][npc], m)
        else:
            out["mobs"][npc] = json.loads(json.dumps(m))
    for f in ("quests", "sell", "qual"):
        for k, v in (b.get(f) or {}).items():
            out.setdefault(f, {}).setdefault(k, v)
    ca, cb = out.setdefault("cal", {"f": 0, "x": 0, "n": 0}), b.get("cal") or {}
    for f in ("f", "x", "n"):
        ca[f] = ca.get(f, 0) + (cb.get(f) or 0)
    for npc, v in (b.get("vend") or {}).items():
        mine = out.setdefault("vend", {}).setdefault(npc, {"i": {}})["i"]
        for k, e in (v.get("i") or {}).items():
            mine.setdefault(k, e)
    for mid, e in (b.get("pvp") or {}).items():
        if mid in out.setdefault("pvp", {}):
            out["pvp"][mid] = {f: out["pvp"][mid].get(f, 0) + e.get(f, 0) for f in set(e) | set(out["pvp"][mid])}
        else:
            out["pvp"][mid] = e
    for kind, levels in (b.get("ctx") or {}).items():
        for lv, e in levels.items():
            t = out.setdefault("ctx", {}).setdefault(kind, {}).setdefault(lv, {"i": {}})
            for f, v in e.items():
                if f == "i":
                    for i, n in v.items():
                        t["i"][i] = t["i"].get(i, 0) + n
                elif isinstance(v, (int, float)):
                    t[f] = t.get(f, 0) + v
    out["runs"] = (out.get("runs") or []) + (b.get("runs") or [])
    out["shares"] = (a.get("shares") or 0) + (b.get("shares") or 0)
    return out


# ------------------------------------------------------------------ a friend's SavedVariables, read (never run)
_TOKEN = re.compile(r"""
    (?P<ws>\s+|--\[(?P<eq>=*)\[.*?\](?P=eq)\]|--[^\n]*)
  | (?P<str>"(?:[^"\\\n]|\\.|\\\n)*")
  | (?P<num>-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?))
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<sym>[{}\[\]=,;])
""", re.S | re.X)
_ESC = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
        "\n": "\n"}


def _unquote(s: str) -> str:
    out, i, end = [], 1, len(s) - 1
    while i < end:
        c = s[i]
        if c == "\\" and i + 1 < end:
            n = s[i + 1]
            if n.isdigit():
                j = i + 1
                while j < min(i + 4, end) and s[j].isdigit():
                    j += 1
                out.append(chr(min(int(s[i + 1:j]), 255)))
                i = j
                continue
            out.append(_ESC.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def parse_saved_variables(text: str, max_nodes: int = 5_000_000) -> dict:
    """The NAME = value assignments of a WoW SavedVariables file, as Python data. Only data is understood
    (tables, strings, numbers, true/false/nil): anything that looks like code is an error, nothing is run.
    Tables whose keys are exactly 1..n come back as lists, like the rest of the helper's saved data."""
    toks = []
    pos, n = 0, len(text)
    while pos < n:
        m = _TOKEN.match(text, pos)
        if not m:
            raise ValueError(f"not saved data near character {pos}")
        pos = m.end()
        if m.lastgroup in ("ws", "eq"):
            continue
        toks.append((m.lastgroup, m.group(m.lastgroup)))
        if len(toks) > max_nodes * 4:
            raise ValueError("too big")
    toks.append(("end", ""))
    i = 0
    count = 0

    def expect(sym):
        nonlocal i
        if toks[i][1] != sym:
            raise ValueError(f"expected {sym!r}")
        i += 1

    def value(depth):
        nonlocal i, count
        if depth > 40:
            raise ValueError("nested too deep")
        count += 1
        if count > max_nodes:
            raise ValueError("too big")
        kind, tok = toks[i]
        i += 1
        if kind == "str":
            return _unquote(tok)
        if kind == "num":
            low = tok.lower().lstrip("-")
            v = float(int(low, 16)) * (-1 if tok.startswith("-") else 1) if low.startswith("0x") else float(tok)
            return int(v) if v.is_integer() and abs(v) < 2 ** 53 else v
        if kind == "name" and tok in ("true", "false"):
            return tok == "true"
        if kind == "name" and tok == "nil":
            return None
        if tok != "{":
            raise ValueError(f"unexpected {tok!r}")
        table, auto = {}, 1
        while toks[i][1] != "}":
            if toks[i][0] == "end":
                raise ValueError("unfinished table")
            k2, t2 = toks[i]
            if t2 == "[":
                i += 1
                key = value(depth + 1)
                expect("]")
                expect("=")
                val = value(depth + 1)
            elif k2 == "name" and toks[i + 1][1] == "=":
                key = t2
                i += 2
                val = value(depth + 1)
            else:
                key, auto = auto, auto + 1
                val = value(depth + 1)
            if isinstance(key, float) and key.is_integer():
                key = int(key)
            if key is not None and val is not None and not isinstance(key, (dict, list)):
                table[key] = val
            if toks[i][1] in (",", ";"):
                i += 1
            elif toks[i][1] != "}":
                raise ValueError("expected , or }")
        i += 1
        keys = list(table)
        if keys and all(isinstance(k, int) and not isinstance(k, bool) for k in keys) \
                and sorted(keys) == list(range(1, len(keys) + 1)):
            return [table[k] for k in range(1, len(keys) + 1)]
        return table

    out = {}
    while toks[i][0] != "end":
        kind, name = toks[i]
        if kind != "name" or toks[i + 1][1] != "=":
            raise ValueError("not saved data")
        i += 2
        out[name] = value(0)
    return out


def _char_ids(db: dict | None) -> list[str]:
    """One-way fingerprints of a file's characters (so a friend's newer file replaces their older one, and your
    own file is recognised) - the names themselves are never kept."""
    snaps = (db or {}).get("snapshots") or {}
    keys = [k for k in (snaps.keys() if isinstance(snaps, dict) else []) if isinstance(k, str)]
    return sorted(hashlib.sha256(("sunstone:" + k.lower()).encode("utf-8")).hexdigest()[:16] for k in keys)


def import_friend(path: str, friends_dir: str, own_db: dict | None) -> tuple[bool, str, dict]:
    """A friend's Sunstone.lua (or a share .json) -> share\\friends\\friend-<id>.json, numbers only.
    Returns (ok, message or the saved file's path, summary)."""
    try:
        size = os.path.getsize(path)
    except OSError as e:
        return False, f"Couldn't open that file ({e.strerror}).", {}
    if size > MAX_FRIEND_FILE:
        return False, "That file is far too big to be Sunstone's saved data.", {}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as e:
        return False, f"Couldn't read that file ({e.strerror}).", {}
    if path.lower().endswith(".json"):
        try:
            raw = json.loads(text)
        except ValueError:
            return False, "That .json file isn't a Sunstone share.", {}
        data = clean_share(raw)
        ids = [hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]]
    else:
        try:
            db = parse_saved_variables(text).get("SunstoneDB")
        except (ValueError, IndexError, RecursionError):
            return False, "That isn't a Sunstone.lua saved-data file (it should be ...\\SavedVariables\\Sunstone.lua).", {}
        if not isinstance(db, dict) or not isinstance(db.get("rec"), dict):
            return False, "That file has no Sunstone recordings in it (is it the Sunstone.lua from SavedVariables?).", {}
        ids = _char_ids(db)
        if ids and set(_char_ids(own_db)) & set(ids):
            return False, "That's your own saved data (it has your characters in it), so it isn't imported.", {}
        data = clean_share(_rec_fields(db["rec"]))
        if not ids:
            ids = [hashlib.sha256(json.dumps(data, sort_keys=True).encode("utf-8")).hexdigest()[:16]]
    summary = summarize(data)
    if not summary["creatures"] and not summary["quests"] and not summary["runs"]:
        return False, "Nothing recorded in that file yet.", summary
    os.makedirs(friends_dir, exist_ok=True)
    target, replaced = None, False
    for name in sorted(os.listdir(friends_dir)):  # the same friend's older file is replaced, not added twice
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(friends_dir, name), encoding="utf-8") as f:
                old = json.load(f)
        except (OSError, ValueError):
            continue
        if set(old.get("ids") or []) & set(ids):
            target, replaced = os.path.join(friends_dir, name), True
            break
    target = target or os.path.join(friends_dir, f"friend-{ids[0][:12]}.json")
    data["ids"] = ids
    data["imported"] = time.strftime("%Y-%m-%d")
    with open(target, "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"))
    summary["replaced"] = replaced
    return True, target, summary


def merge_friends(friends_dir: str, out_path: str) -> dict:
    """Your friends' files -> data\\friends.json (min_reports=1: people you know; the other limits still apply)."""
    if not os.path.isdir(friends_dir):
        return {}
    return merge_folder(friends_dir, out_path, min_reports=1)


CODE = re.compile(r"^\s*SUNSTONE2:(\d+):(.*):END\s*$", re.S)


def read_code(text: str) -> dict | None:
    """A copied text ("SUNSTONE2:length:...:END") or plain JSON -> the share, or None when it isn't whole."""
    m = CODE.match(text or "")
    if m:
        if len(m.group(2)) != int(m.group(1)):
            return None
        text = m.group(2)
    try:
        d = json.loads(text)
    except ValueError:
        return None
    return d if isinstance(d, dict) else None


def merge_folder(folder: str, out_path: str, min_reports: int = 3) -> dict:
    shares = []
    for name in sorted(os.listdir(folder)):
        if name.lower().endswith(".json"):
            try:
                with open(os.path.join(folder, name), encoding="utf-8") as f:
                    shares.append(json.load(f))
            except (OSError, ValueError):
                continue
    data = merge(shares, min_reports)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"))
    return data


if __name__ == "__main__":  # maintainer: python share.py <folder of shares> [min_reports]
    import sys
    src = sys.argv[1]
    mr = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    d = merge_folder(src, os.path.join(here, "data", "community.json"), mr)
    print(f"community.json: {d['shares']} shares -> {len(d['mobs'])} creatures, {len(d['quests'])} quests, {len(d['sell'])} prices")
