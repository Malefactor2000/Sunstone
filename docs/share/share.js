// Sunstone's share page. What you paste stays in this browser until you press Send.
(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  let text = null, sent = false;

  function say(t, cls) { $("say").textContent = t; $("say").className = cls || ""; }

  // a link with the finds in it, the copied text, or the bare text -> the text; null when it isn't whole
  function read(s) {
    s = (s || "").trim();
    let m = s.match(/#s2\.([A-Za-z0-9_-]+)\.end$/);
    if (m) {
      try {
        const b = atob(m[1].replace(/-/g, "+").replace(/_/g, "/"));
        return new TextDecoder().decode(Uint8Array.from(b, (c) => c.charCodeAt(0)));
      } catch (e) { return null; }
    }
    m = s.match(/^SUNSTONE2:(\d+):([\s\S]*):END$/);
    if (m) return m[2].length === Number(m[1]) ? m[2] : null;
    return s.startsWith("{") ? s : null;
  }
  const count = (o) => (Array.isArray(o) ? o.length : o && typeof o === "object" ? Object.keys(o).length : 0);
  const vals = (o) => (o && typeof o === "object" ? Object.values(o) : []);
  const sum = (a, f) => a.reduce((t, x) => t + (Number(f(x)) || 0), 0);

  function show(s) {
    const what = $("what");
    what.textContent = "";
    text = null;
    $("send").disabled = true;
    $("forget").disabled = true;
    $("sure").hidden = true;
    $("backsay").textContent = "";
    if (!s) { say(""); return; }
    const t = read(s);
    let d = null;
    try { d = t && JSON.parse(t); } catch (e) { d = null; }
    if (!d || d.format !== 2 || !/^[0-9a-f]{20}$/.test(d.id || "")) {
      say("That isn't a whole Sunstone text. Copy it again in the game: all of it has to be there.", "bad");
      return;
    }
    const fx = d.fx || {};
    const mobs = vals(d.mobs);
    const rows = [
      [count(d.mobs) + " kinds of creatures", sum(mobs, (m) => (m.k || 0) + ((m.g || {}).k || 0)) + " kills, " + sum(mobs, (m) => (m.l || 0) + ((m.g || {}).l || 0)) + " looted"],
      [count(d.quests) + " quests", count(fx.qi) + " with their rewards"],
      [count(d.vend) + " vendors", ""],
      [count(fx.obj) + count(fx.box) + " chests and crates", count(fx.fish) + " fishing grounds"],
      [count(fx.news) + " new finds", "pets and mounts nobody had on record"],
    ];
    const table = document.createElement("table");
    for (const r of rows) {
      const tr = table.insertRow();
      tr.insertCell().textContent = r[0];
      tr.insertCell().textContent = r[1];
    }
    what.append(table);
    const det = document.createElement("details"), su = document.createElement("summary"), pre = document.createElement("pre");
    su.textContent = "Read the whole text (" + Math.ceil(t.length / 1024) + " KB)";
    det.append(su, pre);
    det.addEventListener("toggle", () => { if (det.open && !pre.textContent) pre.textContent = t; });
    what.append(det);
    text = t;
    sent = false;
    $("send").disabled = false;
    $("send").textContent = "Send";
    $("forget").disabled = false;
    say("This is what would be sent. Nothing has been yet.");
  }

  async function collector() {
    const r = await fetch("collector.txt", { cache: "no-store" });
    const u = (await r.text()).trim().replace(/\/$/, "");
    if (!r.ok || !/^(https:\/\/[a-z0-9.\-]+(\/[a-z0-9\-/]*)?|http:\/\/127\.0\.0\.1:\d+)$/.test(u)) throw new Error("The collector isn't open yet. Please try again another day.");
    return u;
  }
  async function call(method, path, body) {
    const r = await fetch((await collector()) + path, { method, body, headers: body ? { "Content-Type": "application/json" } : {}, credentials: "omit", referrerPolicy: "no-referrer" });
    let d = {};
    try { d = await r.json(); } catch (e) { /* no answer text */ }
    if (!r.ok) throw new Error(d.error || "it answered " + r.status);
    return d;
  }
  $("send").addEventListener("click", async () => {
    if (!text || sent) return;
    $("send").disabled = true;
    say("Sending...");
    try {
      const d = await call("POST", "/share", text);
      sent = true;
      $("send").textContent = "Sent";
      say((d.replaced ? "Sent. Your newer finds replace the older ones. Thank you! " : "Sent. Thank you! They come back to everyone with the next update. ") + "You're done: you can close this page.", "good");
    } catch (e) {
      $("send").disabled = false;
      say("Not sent: " + e.message, "bad");
    }
  });
  $("forget").addEventListener("click", () => {
    if (!text) return;
    $("sure").hidden = false;
    $("sure").focus();
    $("backsay").textContent = "Are you sure? Your finds won't help in the next update.";
  });
  $("sure").addEventListener("click", async () => {
    if (!text) return;
    try {
      await call("DELETE", "/share/" + JSON.parse(text).id);
      $("sure").hidden = true;
      $("backsay").textContent = "Taken back: nothing of yours is kept there now.";
      sent = false;
      $("send").disabled = false;
      $("send").textContent = "Send";
      say("");
    } catch (e) { $("backsay").textContent = "Not taken back: " + e.message; }
  });
  $("text").addEventListener("input", (e) => show(e.target.value));
  function fromLink() {
    if (!location.hash.startsWith("#s2.")) return;
    const link = location.href;
    history.replaceState(null, "", location.pathname); // (so the long link doesn't stay in the address bar and history)
    $("text").value = link.length > 400 ? "(from your link)" : link;
    show(link);
    $("send").focus();
  }
  window.addEventListener("hashchange", fromLink);
  fromLink();
})();
