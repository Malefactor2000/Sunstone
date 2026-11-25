// Sunstone's collector: takes in shared finds (Cloudflare Worker, free tier, with a D1 database bound as DB).
//   POST   /share            a share (JSON, at most 900 KB). The newest one per sender number replaces the older one.
//   DELETE /share/<number>   a sender's own share is deleted (the number is the proof: only the sender knows it)
//   GET    /                 how many senders there are, nothing else
//   GET    /export?after=    for the maintainer (needs the MAINTAINER secret in the Authorization header)
// It keeps no IP addresses: a daily-changing fingerprint of the address only counts how many shares came in today, and is deleted the next day.
// What's inside a share is checked again, number by number, before it's ever used (app/share.py); this only keeps junk out.

const MAX = 900 * 1024, PER_DAY = 12, MOST_SENDERS = 4000;
const ID = /^[0-9a-f]{20}$/;
const TOP = new Set(["format", "ver", "id", "quests", "mobs", "sell", "qual", "cal", "vend", "pvp", "ctx", "runs", "fx", "made"]);
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS", "Access-Control-Allow-Headers": "Content-Type", "Access-Control-Max-Age": "86400" };
const say = (status, body) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...CORS } });

// numbers (and short names) only, not too deep, not too many
function plain(v, depth = 0, left = { n: 250000 }) {
  if (--left.n < 0 || depth > 8) return false;
  if (typeof v === "number") return Number.isFinite(v);
  if (typeof v === "string") return v.length <= 40 && /^[A-Za-z0-9 '\-,.]*$/.test(v);
  if (Array.isArray(v)) return v.every((x) => plain(x, depth + 1, left));
  if (v && typeof v === "object") return Object.entries(v).every(([k, x]) => k.length <= 24 && /^[A-Za-z0-9\-]+$/.test(k) && plain(x, depth + 1, left));
  return false;
}
function problem(text) {
  if (text.length > MAX) return "too big";
  let d;
  try { d = JSON.parse(text); } catch { return "not a whole share (was all of it copied?)"; }
  if (!d || typeof d !== "object" || Array.isArray(d) || d.format !== 2) return "not a Sunstone share";
  if (!ID.test(d.id || "")) return "no sender number";
  for (const k of Object.keys(d)) if (!TOP.has(k)) return "something in it that doesn't belong there";
  if (!plain(d)) return "something in it that isn't a number";
  return null;
}

async function fingerprint(ip, day, salt) {
  const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${salt}|${day}|${ip}`));
  return [...new Uint8Array(h)].slice(0, 10).map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function same(a, b) { // compared without giving away how much of it was right
  const e = new TextEncoder();
  const [x, y] = await Promise.all([crypto.subtle.digest("SHA-256", e.encode(a || "")), crypto.subtle.digest("SHA-256", e.encode(b || ""))]);
  const p = new Uint8Array(x), q = new Uint8Array(y);
  let d = 0;
  for (let k = 0; k < p.length; k++) d |= p[k] ^ q[k];
  return d === 0;
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    const day = new Date().toISOString().slice(0, 10);
    if (req.method === "GET" && url.pathname === "/") {
      const r = await env.DB.prepare("SELECT COUNT(*) AS n FROM shares").first();
      return say(200, { senders: r ? r.n : 0 });
    }
    if (req.method === "POST" && url.pathname === "/share") {
      const len = Number(req.headers.get("Content-Length") || 0);
      if (len > MAX) return say(413, { error: "too big" });
      const text = await req.text();
      const bad = problem(text);
      if (bad) return say(400, { error: bad });
      const id = JSON.parse(text).id;
      const who = await fingerprint(req.headers.get("CF-Connecting-IP") || "", day, env.SALT || "sunstone");
      await env.DB.prepare("DELETE FROM today WHERE day <> ?").bind(day).run();
      const seen = await env.DB.prepare("SELECT n FROM today WHERE who = ? AND day = ?").bind(who, day).first();
      if (seen && seen.n >= PER_DAY) return say(429, { error: "enough for today, thank you" });
      await env.DB.prepare("INSERT INTO today (who, day, n) VALUES (?, ?, 1) ON CONFLICT(who, day) DO UPDATE SET n = n + 1").bind(who, day).run();
      const old = await env.DB.prepare("SELECT 1 AS y FROM shares WHERE id = ?").bind(id).first();
      if (!old) {
        const c = await env.DB.prepare("SELECT COUNT(*) AS n FROM shares").first();
        if (c && c.n >= MOST_SENDERS) return say(503, { error: "full for now" });
      }
      await env.DB.prepare("INSERT INTO shares (id, day, text) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET day = excluded.day, text = excluded.text").bind(id, day, text).run();
      return say(200, { ok: true, replaced: !!old });
    }
    const del = url.pathname.match(/^\/share\/([0-9a-f]{20})$/);
    if (req.method === "DELETE" && del) {
      await env.DB.prepare("DELETE FROM shares WHERE id = ?").bind(del[1]).run();
      return say(200, { ok: true });
    }
    if (req.method === "GET" && url.pathname === "/export") {
      const key = (req.headers.get("Authorization") || "").replace(/^Bearer /, "");
      if (!env.MAINTAINER || !(await same(key, env.MAINTAINER))) return say(404, { error: "not here" });
      const after = url.searchParams.get("after") || "";
      const r = await env.DB.prepare("SELECT id, day, text FROM shares WHERE id > ? ORDER BY id LIMIT 20").bind(after).all();
      return say(200, { shares: r.results || [] });
    }
    return say(404, { error: "not here" });
  },
};
