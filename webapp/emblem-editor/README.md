# CelMod Emblem Editor

A standalone page for designing emblems. It is separate from the game server: upload this folder to
any web host (a PHP host works, no PHP or database is needed) and open `index.html`.

- Pick a skin and color and see the emblem in 3D.
- Choose a power and a shot effect, and fill in the numbers that power uses.
- Copy the emblem, or download every emblem, in the format `addons/sourcemod/data/celmod/collectibles.txt`
  uses. Paste it inside the `"Emblems"` section.
- Import a whole `collectibles.txt`, its `"Emblems"` section, or single emblem blocks to edit them.

Files: `index.html` (the app), `three.module.min.js` (3D library, MIT), `model.json` (the emblem mesh),
`textures/` (the skins that have their own texture). Skins that use stock Half-Life 2 textures are
shown as a flat stand-in color. It must be opened through a web server, not as a local file.
