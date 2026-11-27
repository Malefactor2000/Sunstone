# Changelog

## 2.6.0
A major update: pick your role first (Leveling, Tanking, Healing or DPS, whichever your class can fill), and your gear upgrades are scored for it. Plus an update notice in chat, routes that learn tunnels, and many fixes.

- Update notice: from this version on, when a newer Sunstone is out, it tells you in chat when you log in, and how to get it: in the CurseForge app if you got Sunstone from CurseForge, from GitHub's Releases page if you got it there. Bigger updates are called a major update. Addons can't go online, so it asks the Sunstone of players in your guild, your group and its own hidden channel which version they run. Only version numbers are sent, nothing else is read, and a number from the channel only counts once two different players report it. You can switch it off in the Guide, Settings, Sharing.
- Zephras Isle (the Skyborne island) now has routes: from the island to the airship towers for Mulgore and Dalaran, and back to the island from anywhere, so Skyborne quests get the arrow and the map line again.
- The minimap trail works on Zephras Isle too, around its hills and cliffs. Anywhere Sunstone has no ground data for, it now shows a straight gray line instead of nothing.
- Tunnels and winding passes (like Dun Algaz, from the Wetlands into Loch Modan): the arrow used to point back at the tunnel mouth once you were inside. Sunstone now learns the way through the first time any of your characters walks it, and from then on the arrow, the trail and the map line follow the tunnel's bends. Until then they head for the far end in a straight line. A walk that wanders about on the way (fighting, circling) isn't learned, and any learned before this are forgotten, like the loop the route took out of Thunder Bluff.
- Darkmoon Faire turn-ins (Torn Bear Pelt, Small Furry Paw and the like) said "a quest item, but none of your quests is known to need it" while the Faire was away. They now name their Faire quest. Holiday quests only keep quest items, so cloth and food aren't hoarded for a holiday months away.
- Quests with one start per race or town (like the shaman's Call of Fire): with one already in your log, Sunstone kept offering you the other versions to pick up. It no longer does, and the next step waits on the one you have.
- Arra'chea (Rites of the Earthmother, Mulgore) is where Forever has it, at 48.0, 28.5. Every database had the Classic spot further northeast.
- Forever's own hand-ins: when a quest's hand-in window asks you for items, Sunstone remembers it, and from then on those items name that quest.
- Quests with a tricky spot (the Cozy Sleeping Bag chain's jumps on Thoradin's Wall and down at Stonewrought Dam) show their "How" note on the route's next stop too, not only on the quest's page.
- Your role comes first: the Character page (Gear tab) now opens with "Pick your role", and it has its own row under "Your character". The choices are Leveling, Tanking, Healing or DPS, only the roles your class can really fill (druids are the only ones with all three). Gear upgrades are scored for the role you pick, and your talent plan follows it. The Talents tab offers the same roles: no Tanking for shamans, no DPS for priests or paladins.
- Changing your role scores your gear again at once. Before, the Gear tab kept the old scores until your next level-up, quest or gear change.
- Gear for melee and hunter builds that level or play alone: the stat weights left armor out, so a shaman was offered cloth with a point of Intellect over leather. Armor now counts (20 armor is worth about 1 attack power), so leather and mail win where they should. Healing, caster, raid and dungeon builds keep their own weights. Armor in the Upgrades lists now says cloth, leather, mail or plate.
- Weapons your class can learn but you haven't yet (Fist Weapons for a shaman, say) are no longer mixed in with gear you can use now. They have their own heading, "Learn the weapon skill first", which names the weapon master who teaches it.
- Flights: Sunstone used to think any two of your flight points were linked, so it could send you to fly somewhere the flight master doesn't offer (Kargath to Tarren Mill, before you know Undercity). It now remembers what each flight map you open can actually reach, and only plans those flights. Once you learn a flight point that links them, the flight comes back.

## 2.5.7
- Some items said "Keep it: it starts the quest 0." They start no quest at all: that reason is gone, and they get a normal verdict.

## 2.5.6
- Quests on the other continent: the route now takes you to the boat or zeppelin that goes there (its dock, whether or not you've been there before), with the arrow and the map line leading the way zone by zone. Once you land, it picks the quest up from there.

## 2.5.5
- The search box searches everything Sunstone knows: items, quests (by name, by what they give or teach, by who gives them), creatures and people, things in the world, dungeons and bosses, factions, recipes, sets, enchants, pets, mounts, beasts, your spells, classes, professions, Library Books, the Guide and the settings. Words in any order, part of a word, a letter or two off.
- An item's page now has everything about it: quests that give it or need it, where it drops, chests and crates, vendors, recipes, what it's made into, what it's worth and whether to sell it.
- Forever's own things have their own places: every profession has a Forever page (its camp objects, and every new recipe by skill and by kind, with where the pattern comes from), the Guide has a Campsite page (campfire, Cozy Sleeping Bag, Scarlet Banner, camp objects) and all of Forever's big features one click away.
- Places, people and things have "Show the way": the arrow, the trail and the route on the map.

## 2.5.4
- The search box finds every named place in the game (over 700 of them, towns and camps included) and forgives a letter or two. It also finds factions, dungeons, quests, recipes, items, pets and mounts by name.
- Sold something you need? Sunstone tells you at once, across the top of the screen and in chat, while it's still under the vendor's Buyback tab: quest items, materials your professions use, upgrades, rare finds, things worth far more at the Auction House, and anything you mark Keep (Gold, Your bags). It can be switched off in Settings.

## 2.5.3
- Minimap: quest marks from far away no longer show as if they were next to you. Hand-ins that are ready, and quests to pick up that are further off, ride on the rim, small and dimmed, with the distance when you hover.

## 2.5.2
First public release.

- The world map is one smooth sheet: the wheel zooms from the whole world into a camp, dragging moves it, in the game's own parchment style with the land you've explored drawn in. Your route and its stops, quests, flight masters, boats and dungeon doors are on it, and every stop in the route list has a Zoom in button.
- The route's lines are drawn over the explored land, through every zone on the way; show the whole route, just the next stop, or nothing. "Where I've been" draws the way you came when you want to retrace your steps.
- Sharing finds (optional): Sunstone asks once, Yes or No, and there's a Share button at the top of its window. Help everyone's numbers by hand with one link (a line in chat reminds you once a week), or by itself with a small program. The page shows exactly what's in it. What players share comes back in updates: drops and XP of Forever's creatures, vendor prices, sources of pets and mounts.
- Sunstone remembers more of what you see: chests, crates and fishing, quest rewards, how long fights take, XP by level, and pets and mounts from sources nobody had on record.
- XP runs: the route picks up, does and hands in the quests around you that pay best for the time, in one round with your own. Every quest has On and Off, and follow-ups join as they open.
- The window can be made bigger or smaller: drag its bottom right corner, use A- and A+, or type `/sun size 130`. Text, icons and 3D pictures grow together.
- Character page: your character in 3D with every stat explained in real numbers, what each spell does to an enemy of a level you pick, and trying gear on.
- Pet planner for hunters: any beast in 3D at your level, its skills, training points and how two pets compare. It follows your target.
- Talent trees with the plan on them and what one more point would do.
- 3D previews of dungeon bosses, demons, companion pets and mounts.
- Quest search: by name, by what a quest gives, or by part of a word, with the whole chain on a map.
