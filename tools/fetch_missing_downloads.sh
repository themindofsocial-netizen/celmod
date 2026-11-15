#!/bin/bash
# Copies the files maps need, but the server doesn't have, from the FastDL into the game folder.
#
# celmod-mapdownloads writes what each map needs and the server is missing to
# addons/sourcemod/data/celmod/missing_downloads/<map>.txt. This fetches every file listed there from the
# FastDL (the .bz2 copy, or the plain file) and puts it, unpacked, where the server looks for it.
#
#   tools/fetch_missing_downloads.sh /serverdata/serverfiles/hl2mp [https://celmod.net/fastdl]
#
# Run it on the game server (as the user that owns the game files), then change map.

set -u
GAME_DIR="${1:?usage: $0 <path to hl2mp> [fastdl url]}"
FASTDL="${2:-https://celmod.net/fastdl}"
LIST_DIR="$GAME_DIR/addons/sourcemod/data/celmod/missing_downloads"

if [ ! -d "$LIST_DIR" ]; then
	echo "No missing files listed yet ($LIST_DIR). Start the server on a map first."
	exit 0
fi

# A web page instead of the file (a web host answering a missing file with its home page) is never kept.
not_html() { ! head -c 512 "$1" 2>/dev/null | grep -qi '<!doctype html\|<html'; }

got=0; failed=0
while IFS= read -r file; do
	file="${file%$'\r'}"
	case "$file" in ""|//*) continue ;; esac
	dest="$GAME_DIR/$file"
	[ -f "$dest" ] && continue
	mkdir -p "$(dirname "$dest")"
	if curl -fsSL "$FASTDL/$file.bz2" -o "$dest.bz2" && [ "$(head -c 3 "$dest.bz2")" = "BZh" ] && bunzip2 "$dest.bz2" 2>/dev/null; then
		got=$((got+1)); echo "got  $file"
	elif rm -f "$dest.bz2" && curl -fsSL "$FASTDL/$file" -o "$dest" && not_html "$dest"; then
		got=$((got+1)); echo "got  $file"
	else
		rm -f "$dest" "$dest.bz2"
		failed=$((failed+1)); echo "MISSING on the FastDL too: $file"
	fi
done < <(cat "$LIST_DIR"/*.txt 2>/dev/null | sort -u)

echo "Done: $got fetched, $failed not on the FastDL either. Change map so they're sent to players."
