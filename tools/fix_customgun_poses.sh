#!/bin/bash
# Sets how each CelMod celwep is held (the player's pose) in its Custom Guns weapon script.
#
# Custom Guns takes the pose from the script's "anim_prefix", and only knows these:
#   "missile launcher" = like the RPG     "bow"   = like the crossbow
#   "crowbar"          = like the crowbar "gauss" = like the gravity gun
#
#   tools/fix_customgun_poses.sh /serverdata/serverfiles/hl2mp
#
# Each script it changes is backed up next to it as .bak. Restart the server (or change map twice) afterwards,
# as Custom Guns reads the scripts when it loads.

GAME_DIR="${1:?usage: $0 <path to hl2mp>}"

declare -A POSE=(
	[weapon_cm_meloncannon]="missile launcher"
	[weapon_cm_bladebow]="bow"
	[weapon_cm_sawgun]="gauss"
	[weapon_cm_axe]="crowbar"
	[weapon_cm_firesword]="crowbar"
	[weapon_cm_iceblade]="crowbar"
	[weapon_cm_powerblade]="crowbar"
	[weapon_cm_pickaxe]="crowbar"
	[weapon_cm_shovel]="crowbar"
	[weapon_cm_sunflower]="crowbar"
)

found=0
for gun in "${!POSE[@]}"; do
	while IFS= read -r file; do
		found=$((found+1))
		pose="${POSE[$gun]}"
		[ -f "$file.bak" ] || cp "$file" "$file.bak"
		if grep -qi '"anim_prefix"' "$file"; then
			sed -i -E "s/(\"anim_prefix\"[[:space:]]+)\"[^\"]*\"/\1\"$pose\"/I" "$file"
		else
			# No anim_prefix yet: added as the first line inside the script's top block.
			sed -i -E "0,/\{/s//{\n\t\"anim_prefix\"\t\"$pose\"/" "$file"
		fi
		echo "$gun -> \"$pose\"  ($file)"
	done < <(find "$GAME_DIR" -path "$GAME_DIR/addons" -prune -o -iname "$gun.txt" -print)
done

[ "$found" -eq 0 ] && echo "No weapon_cm_*.txt scripts found under $GAME_DIR (are the Custom Guns weapons installed?)."
echo "Done. Restart the server so Custom Guns reads the scripts again."
