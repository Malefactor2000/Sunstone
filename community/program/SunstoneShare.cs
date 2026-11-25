// Sunstone Share: sends the finds you switched on in the game (Guide, Share), by itself. Optional.
//
// What it reads:  one entry, "shareOut", in  WTF\Account\<account>\SavedVariables\Sunstone.lua . The addon only writes that entry while
//                 sharing is on in the game. Nothing else of the file is used, and no other file is read.
// What it sends:  that text, as it is, to Sunstone's collector (the address is on Sunstone's share page). At most twice a day, only when
//                 it changed. Nothing about you or this PC.
// What it writes: its own settings in  %AppData%\SunstoneShare , and, if you tick "Start with Windows", one entry under your user's Run key.
// It never touches the game, its memory or its files.
//
// Build:  %WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe /target:winexe /win32icon:sunstone.ico SunstoneShare.cs   (nothing else needed)
// GPL-3.0, like the rest of Sunstone.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Sunstone Share")]
[assembly: AssemblyProduct("Sunstone Share")]
[assembly: AssemblyDescription("Sends the finds you chose to share from the Sunstone addon")]
[assembly: AssemblyVersion("1.0.0.0")]

static class Program
{
    const string Page = "https://malefactor2000.github.io/Sunstone/share/";
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const int MaxText = 900 * 1024;
    static readonly TimeSpan Wait = TimeSpan.FromHours(12);
    static readonly string Home = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SunstoneShare");
    static string settingsDir = Home, server, folder, lastStatus = "Nothing sent yet.";
    static Dictionary<string, string> set = new Dictionary<string, string>();

    // ---------------------------------------------------------------- settings
    static void Load()
    {
        try
        {
            foreach (string line in File.ReadAllLines(Path.Combine(settingsDir, "settings.txt")))
            {
                int k = line.IndexOf('=');
                if (k > 0) set[line.Substring(0, k)] = line.Substring(k + 1);
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
    static string Get(string k) { string v; return set.TryGetValue(k, out v) ? v : ""; }
    static void Put(string k, string v)
    {
        set[k] = v;
        try
        {
            Directory.CreateDirectory(settingsDir);
            var sb = new StringBuilder();
            foreach (var p in set) sb.Append(p.Key).Append('=').Append(p.Value).Append("\r\n");
            File.WriteAllText(Path.Combine(settingsDir, "settings.txt"), sb.ToString());
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    // ---------------------------------------------------------------- the game's folder and the addon's entry
    static string FindFolder()
    {
        var tries = new List<string>();
        foreach (string hive in new[] { @"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft", @"SOFTWARE\Blizzard Entertainment\World of Warcraft" })
            try
            {
                using (RegistryKey k = Registry.LocalMachine.OpenSubKey(hive))
                {
                    string p = k == null ? null : k.GetValue("InstallPath") as string;
                    if (!string.IsNullOrEmpty(p)) { tries.Add(p); string up = Path.GetDirectoryName(p.TrimEnd('\\')); if (up != null) tries.Add(Path.Combine(up, "_forever_")); }
                }
            }
            catch (Exception) { }
        foreach (string d in new[] { "C", "D", "E", "F", "G" })
            foreach (string p in new[] { @":\Program Files (x86)\World of Warcraft\_forever_", @":\World of Warcraft\_forever_", @":\Games\World of Warcraft\_forever_", @":\Program Files\World of Warcraft\_forever_" })
                tries.Add(d + p);
        foreach (string t in tries) if (Good(t)) return t;
        return "";
    }
    static bool Good(string f) { try { return !string.IsNullOrEmpty(f) && Directory.Exists(Path.Combine(f, @"WTF\Account")); } catch (ArgumentException) { return false; } }
    static List<string> Files()
    {
        var o = new List<string>();
        if (!Good(folder)) return o;
        try
        {
            foreach (string a in Directory.GetDirectories(Path.Combine(folder, @"WTF\Account")))
            {
                string f = Path.Combine(a, @"SavedVariables\Sunstone.lua");
                if (File.Exists(f)) o.Add(f);
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        return o;
    }
    // the text inside  ["shareOut"] = { ... ["text"] = "..." ... } ; null when sharing is off in the game
    public static string Extract(string lua)
    {
        int at = lua.IndexOf("[\"shareOut\"] = {", StringComparison.Ordinal);
        if (at < 0) return null;
        int i = at + 16, depth = 1;
        while (i < lua.Length && depth > 0)
        {
            char c = lua[i];
            if (c == '"')
            {
                int end = End(lua, i);
                if (end < 0) return null;
                string word = lua.Substring(i + 1, end - i - 1);
                if (depth == 1 && i > 0 && lua[i - 1] == '[' && word == "text")
                {
                    int q = lua.IndexOf('"', end + 1);
                    if (q < 0) return null;
                    int e2 = End(lua, q);
                    return e2 < 0 ? null : Plain(lua.Substring(q + 1, e2 - q - 1));
                }
                i = end;
            }
            else if (c == '{') depth++;
            else if (c == '}') depth--;
            i++;
        }
        return null;
    }
    static int End(string s, int open)
    {
        for (int k = open + 1; k < s.Length; k++)
        {
            if (s[k] == '\\') { k++; continue; }
            if (s[k] == '"') return k;
        }
        return -1;
    }
    static string Plain(string s)
    {
        var sb = new StringBuilder(s.Length);
        for (int k = 0; k < s.Length; k++)
        {
            if (s[k] == '\\' && k + 1 < s.Length) { k++; sb.Append(s[k] == 'n' ? '\n' : s[k]); }
            else sb.Append(s[k]);
        }
        return sb.ToString();
    }
    static readonly Regex Id = new Regex("\"id\":\"([0-9a-f]{20})\"");
    static bool Whole(string t) { return t != null && t.Length > 20 && t.Length < MaxText && t[0] == '{' && t[t.Length - 1] == '}' && t.Contains("\"format\":2") && Id.IsMatch(t); }
    static string Hash(string t)
    {
        using (var h = SHA256.Create()) return BitConverter.ToString(h.ComputeHash(Encoding.UTF8.GetBytes(t))).Replace("-", "").Substring(0, 32);
    }

    // ---------------------------------------------------------------- sending
    static string Web(string method, string url, string body)
    {
        var q = (HttpWebRequest)WebRequest.Create(url);
        q.Method = method;
        q.Timeout = 30000;
        q.UserAgent = "SunstoneShare/1.0";
        q.AllowAutoRedirect = false;
        if (body != null)
        {
            byte[] b = Encoding.UTF8.GetBytes(body);
            q.ContentType = "application/json";
            q.ContentLength = b.Length;
            using (Stream s = q.GetRequestStream()) s.Write(b, 0, b.Length);
        }
        using (var r = (HttpWebResponse)q.GetResponse())
        using (var rd = new StreamReader(r.GetResponseStream())) return rd.ReadToEnd();
    }
    static string Server()
    {
        if (!string.IsNullOrEmpty(server)) return server;
        string t = Web("GET", Page + "collector.txt", null).Trim();
        if (!Regex.IsMatch(t, @"^https://[a-z0-9\-\.]+(/[a-z0-9\-/]*)?$")) throw new WebException("the collector isn't open yet");
        return server = t.TrimEnd('/');
    }
    static string Why(Exception e)
    {
        var w = e as WebException;
        if (w != null && w.Response != null)
            try { using (var rd = new StreamReader(w.Response.GetResponseStream())) { Match m = Regex.Match(rd.ReadToEnd(), "\"error\":\"([^\"]{1,80})\""); if (m.Success) return m.Groups[1].Value; } }
            catch (IOException) { }
        return e.Message;
    }
    static readonly object gate = new object();
    static void Check(bool now)
    {
        lock (gate)
        {
            List<string> files = Files();
            if (files.Count == 0) { lastStatus = Good(folder) ? "No Sunstone data yet: log in with the addon on, then log out." : "WoW Forever's folder wasn't found: choose it in this menu."; return; }
            int off = 0, sent = 0, same = 0;
            string err = null;
            foreach (string f in files)
            {
                string t;
                try { t = Extract(File.ReadAllText(f, Encoding.UTF8)); }
                catch (IOException) { continue; } // (the game is writing it: next time)
                catch (UnauthorizedAccessException) { continue; }
                if (!Whole(t)) { off++; continue; }
                string id = Id.Match(t).Groups[1].Value, h = Hash(t);
                long last;
                long.TryParse(Get("at." + id), out last);
                if (Get("sent." + id) == h) { same++; continue; }
                if (!now && DateTime.UtcNow - new DateTime(last, DateTimeKind.Utc) < Wait) { same++; continue; }
                try
                {
                    Web("POST", Server() + "/share", t);
                    Put("sent." + id, h);
                    Put("at." + id, DateTime.UtcNow.Ticks.ToString());
                    sent++;
                }
                catch (Exception e) { err = Why(e); server = fixedServer; }
            }
            string when = DateTime.Now.ToString("d MMM HH:mm");
            if (err != null) lastStatus = "Not sent (" + err + "). Trying again later.";
            else if (sent > 0) lastStatus = "Sent " + when + ". Thank you!";
            else if (same > 0) lastStatus = "Nothing new since the last time.";
            else lastStatus = "Sharing is off in the game (the Share finds button).";
        }
    }
    static string fixedServer;
    static void Forget()
    {
        lock (gate)
        {
            var ids = new List<string>();
            foreach (string k in set.Keys) if (k.StartsWith("sent.")) ids.Add(k.Substring(5));
            int n = 0;
            try { foreach (string id in ids) { Web("DELETE", Server() + "/share/" + id, null); n++; } lastStatus = n > 0 ? "What you sent is deleted." : "Nothing of yours is there."; }
            catch (Exception e) { lastStatus = "Not deleted (" + Why(e) + ")."; return; }
            foreach (string id in ids) { set.Remove("sent." + id); set.Remove("at." + id); }
            Put("v", "1");
        }
    }

    // ---------------------------------------------------------------- the tray
    static bool AtStart
    {
        get { using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKey)) return k != null && k.GetValue("SunstoneShare") != null; }
        set
        {
            using (RegistryKey k = Registry.CurrentUser.CreateSubKey(RunKey))
                if (value) k.SetValue("SunstoneShare", "\"" + Application.ExecutablePath + "\""); else k.DeleteValue("SunstoneShare", false);
        }
    }
    static void Tray()
    {
        if (Get("ok") != "1")
        {
            string text = "Sunstone Share sends the finds you switched on in the game (Sunstone, Guide, Share) to Sunstone's collector, by itself, at most twice a day.\n\n" +
                "It sends only that text: numbers about creatures, quests, chests and vendors. No character, realm or account name, nothing about you or this PC.\n\n" +
                "It sits by the clock. Right-click it to read the text, send now, stop, or delete what you've sent.\n\nStart it?";
            if (MessageBox.Show(text, "Sunstone Share", MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return;
            Put("ok", "1");
        }
        var icon = new NotifyIcon { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath), Text = "Sunstone Share", Visible = true };
        var menu = new ContextMenuStrip();
        var status = new ToolStripMenuItem("") { Enabled = false };
        var start = new ToolStripMenuItem("Start with Windows");
        ThreadStart later = delegate { Check(false); };
        menu.Items.Add(status);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Send now", null, delegate { new Thread(delegate() { Check(true); icon.ShowBalloonTip(4000, "Sunstone Share", lastStatus, ToolTipIcon.None); }) { IsBackground = true }.Start(); });
        menu.Items.Add("Read what would be sent", null, delegate
        {
            foreach (string f in Files())
            {
                string t = null;
                try { t = Extract(File.ReadAllText(f, Encoding.UTF8)); } catch (IOException) { }
                if (!Whole(t)) continue;
                Directory.CreateDirectory(settingsDir);
                string p = Path.Combine(settingsDir, "what-would-be-sent.txt");
                File.WriteAllText(p, t);
                Process.Start(p);
                return;
            }
            MessageBox.Show("Nothing: sharing is off in the game, or you haven't logged out since you switched it on.", "Sunstone Share");
        });
        menu.Items.Add("The share page", null, delegate { Process.Start(Page); });
        menu.Items.Add("WoW Forever's folder...", null, delegate
        {
            using (var d = new FolderBrowserDialog { Description = "The folder named _forever_ in your World of Warcraft folder", SelectedPath = folder ?? "", ShowNewFolderButton = false })
                if (d.ShowDialog() == DialogResult.OK)
                {
                    string p = Good(d.SelectedPath) ? d.SelectedPath : Path.Combine(d.SelectedPath, "_forever_");
                    if (!Good(p)) { MessageBox.Show("That folder has no WTF\\Account in it.", "Sunstone Share"); return; }
                    folder = p;
                    Put("folder", p);
                    new Thread(later) { IsBackground = true }.Start();
                }
        });
        menu.Items.Add(start);
        menu.Items.Add("Delete what I've sent", null, delegate
        {
            if (MessageBox.Show("Delete everything this PC has sent to Sunstone's collector? (Numbers already in a released version stay there, with everyone's.)", "Sunstone Share", MessageBoxButtons.YesNo) != DialogResult.Yes) return;
            new Thread(delegate() { Forget(); icon.ShowBalloonTip(4000, "Sunstone Share", lastStatus, ToolTipIcon.None); }) { IsBackground = true }.Start();
        });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, delegate { icon.Visible = false; Application.Exit(); });
        start.Click += delegate { try { AtStart = !AtStart; } catch (UnauthorizedAccessException) { } };
        menu.Opening += delegate { status.Text = lastStatus; start.Checked = AtStart; };
        icon.ContextMenuStrip = menu;
        var timer = new System.Windows.Forms.Timer { Interval = 10 * 60 * 1000, Enabled = true };
        timer.Tick += delegate { new Thread(later) { IsBackground = true }.Start(); };
        new Thread(later) { IsBackground = true }.Start();
        Application.Run();
        icon.Dispose();
    }

    [STAThread]
    static int Main(string[] args)
    {
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072 | (SecurityProtocolType)768;
        bool once = false, now = false, forget = false;
        for (int k = 0; k < args.Length; k++)
        {
            if (args[k] == "--once") once = true;
            else if (args[k] == "--now") now = true;
            else if (args[k] == "--forget") forget = true;
            else if (args[k] == "--folder" && k + 1 < args.Length) folder = args[++k];
            else if (args[k] == "--settings" && k + 1 < args.Length) settingsDir = args[++k];
            else if (args[k] == "--server" && k + 1 < args.Length) // only for testing on this PC
            {
                string s = args[++k];
                if (Regex.IsMatch(s, @"^http://127\.0\.0\.1:\d+$")) { server = s; fixedServer = s; }
            }
        }
        Load();
        if (string.IsNullOrEmpty(folder)) folder = Get("folder");
        if (!Good(folder)) folder = FindFolder();
        if (once || forget)
        {
            if (forget) Forget(); else Check(now);
            Directory.CreateDirectory(settingsDir);
            File.WriteAllText(Path.Combine(settingsDir, "status.txt"), lastStatus);
            return lastStatus.StartsWith("Sent") || lastStatus.StartsWith("Nothing") || lastStatus.StartsWith("What") ? 0 : 1;
        }
        bool first;
        using (new Mutex(true, "SunstoneShare", out first))
        {
            if (!first) return 0;
            Application.EnableVisualStyles();
            Tray();
        }
        return 0;
    }
}
