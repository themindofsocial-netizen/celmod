# Celweps (Custom Guns weapon scripts)

These make CelMod's celweps real, separate weapons. They need the
[Custom Guns](https://github.com/Alienmario/customguns-hl2dm) plugin (and DHooks).

1. Install Custom Guns as its readme says (configs, gamedata and plugins into `addons/sourcemod`).
2. Copy these `weapon_cm_*.txt` files into `hl2mp/scripts/` (or `hl2mp/custom/<folder>/scripts/`).
3. Put the models they name on the server: `models/celweps/a1, a2, a5, a8` (and their `_v` view models) and
   `models/weapons/hl2meleepack/v_shovel.mdl`, with their materials. Missing models show as errors.
4. Optional: set `customguns_default ""` so Custom Guns does not hand everyone its default weapon.

Players get a celwep by pressing E on a weapon cel they own (`!weapon <name>` spawns one). It goes into their
weapon menu; Custom Guns' weapon wheel (hold reload) switches to it. Several can be carried at once.

Without Custom Guns, celweps still work: the player gets the stock weapon named by `base` in collectibles.txt.
