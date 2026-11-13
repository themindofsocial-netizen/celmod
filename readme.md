![alt text](https://raw.githubusercontent.com/themindofsocial-netizen/celmod/refs/heads/main/images/gh-logo.png "CelMod Logo")

**|CelMod|** is a fully customized building experience, and extra features to enhance the standard gameplay.

Latest release is *3.0.0*.

Built against SourceMod *1.12.0-git7198* and Metamod: Source *1.12.0-git1219*.

This plugin uses [Updater](https://github.com/rockzehh/updater) to update its files, and is required.
This plugin uses [More Colors](https://forums.alliedmods.net/showthread.php?t=185016) for the text color, and [StudioHdr](https://forums.alliedmods.net/showthread.php?t=333857) for advanced model information. It is required if you want to recompile the plugin.

## Installation

Extract the zip file into your server directory with [SourceMod](https://www.sourcemod.net/) and [Metamod: Source](https://www.sourcemm.net/) installed.

## Commands
Command | Description | Aliases | Type | Extra
--- | --- | --- | --- | ---
+copy/-copy|Starts copying and moving the prop you are looking at.|None|Client|
+move/-move|Starts moving the prop you are looking at.|None|Client|
v_alpha|Changes the transparency on the prop you are looking at.|v_amt|Client|
v_ammo|Creates a ammo bit that will give ammo when the player touches it.|None|Client|
v_ammocrate|Creates a ammo crate bit that will give ammo to the player.|None|Client|
v_auction|Auctions an emblem, hat or weapon above the Guess Booth, or cancels the auction.|None|Admin|
v_autobuild|Stacks props on the x, y and z axis.|None|Admin|
v_axis|Creates a marker to the player showing every axis.|v_mark, v_marker|Client|
v_balance|Gets the players current balance.|None|Client|
v_bid|Bids on the item being auctioned above the Guess Booth.|None|Client|
v_blacklist|Adds/removes a prop from the spawn blacklist.|None|Admin|
v_button|Spawns a button trigger bit.|None|Client|
v_buy|Purchases the current entity you are looking at or command you specified.|None|Client|
v_buymodel|Buys a player model.|None|Client|
v_charger|Creates a health/suit charger bit that will give health/suit to the player.|None|Client|
v_cl|Shows your balance, or drops an amount of cleers for another player to pick up.|None|Client|
v_clear|Deletes one of your saved builds.|None|Client|
v_color|Colors the prop you are looking at.|v_paint|Client|
v_colorlist|Displays the color list.|v_colors|Client|[Color List](https://delaware.rockzehh.net/colors.html)
v_commandlist|Displays the command list.|v_cmds, v_commands|Client|[Command List](https://delaware.rockzehh.net/cmds.html)
v_copy|Copies the prop you are looking at into your copy buffer.|None|Client|
v_delete|Removes the prop you are looking at.|v_del, v_remove|Client|
v_delreward|Removes the reward pickup you are looking at.|None|Admin|
v_delzone|Deletes the area you are standing in.|None|Admin|
v_dm|Changes the deathmatch setting within the land.|v_landdeathmatch|Client|
v_door|Spawns a working door cel.|None|Client|
v_drop|Teleports the entity you are looking at to the floor.|None|Client|
v_effect|Spawns a working effect cel.|v_emitter|Client|
v_effectlist|Displays the effect list.|v_effects|Client|[Effects List](https://delaware.rockzehh.net/effects.html)
v_emblem|Spawns an emblem you own, or disables your active emblem (off).|None|Client|
v_emblemdrop|Starts an emblem drop.|None|Admin|
v_emblems|Lists the emblems and hats you own.|v_hats, v_inventory|Client|
v_fadecolor|Fades the prop you are looking at between two colors.|None|Client|
v_fire|Spawns a fire effect cel.|None|Client|
v_firstperson|Switches back to the first person view.|None|Client|
v_fly|Enables/disables nocip on the player.|None|Client|
v_freeze|Freezes the prop you are looking at.|v_freezeit|Client|
v_give|Gives the entity you are looking at to another player.|None|Client|
v_giveitem|Gives an emblem or hat to a player.|None|Admin|
v_givemodel|Gives a player model to a player.|None|Admin|
v_god|Enables/disables breakability on the prop you are looking at.|None|Client|
v_gravity|Changes the gravity within the land.|v_landgravity|Client|
v_guess|Guesses the winning prop at the Guess Booth. One guess per map.|None|Client|
v_guessbooth|Moves the Guess Booth to where you are standing and picks new props.|None|Admin|
v_hat|Spawns a hat you own, or takes off your hat (off).|None|Client|
v_hide|Hides another player's entities from your view.|None|Client|
v_internet|Creates a working internet cel.|None|Client|
v_ladder|Creates a working ladder cel.|None|Client|
v_land|Creates a building zone.|None|Client|
v_landban|Bans a player from your land.|None|Client|
v_landcolor|Changes the color of your land's border.|None|Client|
v_landkick|Kicks a player out of your land for 10 seconds.|None|Client|
v_landslay|Slays a player, or everyone, inside your land.|None|Client|
v_landunban|Lets a banned player back into your land.|None|Client|
v_light|Creates a working light cel.|None|Client|
v_link|Creates a link between a trigger bit and an entity.|None|Client|
v_load|Loads entites from a save file.|None|Client|
v_lock|Locks the cel you are looking at.|None|Client|
v_message|Spawns a message cel that shows your text to whoever uses it.|None|Client|
v_model|Replaces the model on the entity you are looking at.|None|Client|
v_moveto|Moves one of your entities onto another entity.|None|Client|
v_noclip|Enables/disables noclip on the player.|None|Client|
v_nokill|Enables/disables godmode on the player.|None|Client|
v_nudge|Moves where held emblems, celweps or your hat sit a little, and saves it.|None|Admin|
v_palette|Colors the prop you are looking at with your own red, green and blue values.|None|Client|
v_paste|Pastes the prop in your copy buffer where you are looking at.|None|Client|
v_playermodel|Wears a player model you own, or goes back to your own (off).|None|Client|
v_playermodels|Lists the player models and their prices.|None|Client|
v_powerbooth|Moves the Power Booth to where you are looking.|None|Admin|
v_proplist|Displays the prop list.|v_props|Client|[Prop List](https://delaware.rockzehh.net/props/index.html)
v_release|Releases the entity you are looking at from a weld.|None|Client|
v_renderfx|Changes the RenderFX on what prop you are looking at.|None|Client|
v_reward|Creates a reward pickup that gives an emblem or hat once per player.|None|Admin|
v_rotate|Rotates the prop you are looking at.|None|Client|
v_save|Saves all server entties that are in your land.|None|Client|
v_sell|Sells the entity you are looking at.|None|Client|
v_setbalance|Sets the balance of the client you are specifing.|None|Admin|
v_setowner|Sets the owner of the prop you are looking at.|None|Admin|
v_seturl|Sets the url of the internet cel you are looking at|None|Client|
v_show|Shows a hidden player's entities again.|None|Client|
v_smove|Moves the prop you are looking at on it's origin|v_pmove|Client|
v_solid|Enables/disables solidicity on the prop you are looking at.|None|Client|
v_sound|Spawns a sound cel that plays a sound when used.|None|Client|
v_spawn|Spawns a prop by name.|v_p, v_s|Client|
v_stack|Stacks props on the x, y and z axis.|None|Client|
v_stackinfo|Gets the origin difference between props for help stacking.|None|Client|
v_stand|Resets the angles on the prop you are looking at.|v_straight, v_straighten|Client|
v_stuck|Respawns you.|None|Client|
v_switch|Switches the side the hud is on the screen.|None|Client|
v_takemodel|Takes a player model away from a player.|None|Admin|
v_teleport|Spawns a teleport pad. Use it twice: the first pad sends players to the second.|None|Client|
v_thirdperson|Switches to a third person view so you can see your emblem and hat.|None|Client|
v_trade|Offers the entity you are looking at in a trade with another player.|None|Client|
v_tune|Sets where held emblems, celweps or your hat sit, and saves it.|None|Admin|
v_turn|Rotates the prop you are looking at.|None|Client|
v_undo|Removes the last entity you spawned.|None|Client|
v_unfreeze|Unfreezes the prop you are looking at.|v_unfreezeit|Client|
v_unlock|Unlocks the cel you are looking at.|None|Client|
v_weapon|Spawns a weapon cel you own, or puts your celwep away (off).|None|Client|
v_weapons|Lists the emblems, hats and weapons you own.|None|Client|
v_weld|Welds one of your entities to another so they move together.|None|Client|
v_wep|Creates a weapon bit that will give a weapon when the player touches it.|None|Client|
v_weps|Gives you every weapon.|None|Client|
v_zone|Creates an event or restricted area. Use it at one corner, then at the opposite corner.|None|Admin|
v_zones|Lists the event and restricted areas on this map.|None|Client|

## Developer Commands
Command | Description | Type
--- | --- | ---
cm_exportcolorlist|Exports the color list into a text or html file in 'data/celmod/exports'.|Server
cm_exportcommandlist|Exports the command list into a text or html file in 'data/celmod/exports'.|Server
cm_exportproplist|Exports the prop list into a text or html file in 'data/celmod/exports'.|Server

For the most current command list, [click here](https://raw.githubusercontent.com/themindofsocial-netizen/celmod/main/addons/sourcemod/data/celmod/exports/commandlist_export.txt).

## Website Database (celmod-database)
`celmod-database` shares live server data with the [|CelMod| website](https://github.com/rockzehh/celmod-website) through a MySQL/MariaDB database: who is online, playtime, balances, unlocks, props/cels spawned, map history and daily stats. It also delivers orders placed in the website shop - the server re-checks the price and balance in-game before charging, so balances stay server-side.

Add a `"celmod"` entry to `addons/sourcemod/configs/databases.cfg` (MySQL driver) pointing at the same database the website uses. Tables are created automatically.

ConVar | Default | Description
--- | --- | ---
cm_db_config|celmod|databases.cfg entry to use.
cm_db_server_id|1|Unique ID for this server (match `server.id` in the website config).
cm_db_address||Public ip:port shown on the website (auto-detected if empty).
cm_db_heartbeat|15.0|Seconds between live status updates.
cm_db_order_poll|5.0|Seconds between checks for web shop orders.
cm_db_sample|300.0|Seconds between player count samples for the activity chart.

`cm_db_status` (root admin) shows whether the database is connected.

## Additional Information
This plugin is designed with Half-Life 2: Deathmatch in mind. This may work on other source games, but it is not officially tested. All of the plugins functions are open to other plugins using natives, thus making multiple plugins a breeze.

## Contributing
Currently, this project is not accepting outside contributions to the official repository.
