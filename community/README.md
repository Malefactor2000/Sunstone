# Shared finds

What players choose to share, and how it comes back to everyone. All of it is optional; sharing is off until it's switched on in the game (`/sun share`).

| Part | What it is |
|---|---|
| `../Finds.lua`, `../Share.lua` | The addon's side: what's recorded, the text that's shared, the switch, the link |
| `../docs/share` | The page finds are sent from by hand |
| `program/SunstoneShare.cs` | The small Windows program that sends them by itself. One file; build it with the C# compiler Windows has: `%WINDIR%\\Microsoft.NET\\Framework64\\v4.0.30319\\csc.exe /target:winexe SunstoneShare.cs` |
| `collector/worker.js` | What takes them in (a Cloudflare Worker with a D1 database). Keeps the newest share per sender number, no IP addresses |
| `share.py`, `build_data.py` | Checks every share number by number, throws out what's far off everyone else's, pools the rest into `CommunityData.lua` |

A number is only used when several players agree: three for drops, coins and XP of a creature, two for prices, places and names. The source of a pet or mount shows from one report, as not confirmed.
