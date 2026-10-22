#!/bin/sh
# Writes web/data/museum.json: the museum exactly as crystalminer builds it, recorded by tools/cmdump in a fresh world on a headless Luanti server. Run from anywhere; needs Luanti.
#
# Usage: tools/export_museum.sh [path-to-luanti-binary]
# Without an argument it looks for luantiserver, minetestserver, luanti or minetest on the PATH.
#
# The game is copied under its own game id (cmexport), because a Luanti installed with a games/crystalminer of its own (for example a link to a working copy) would otherwise load that instead.
set -e
cd "$(dirname "$0")/.."
REPO="$(pwd)"

SERVER="$1"
if [ -z "$SERVER" ]; then
	for b in luantiserver minetestserver luanti minetest; do
		if command -v "$b" >/dev/null 2>&1; then SERVER="$(command -v "$b")"; break; fi
	done
fi
if [ -z "$SERVER" ]; then echo "No Luanti binary found. Pass its path: tools/export_museum.sh /path/to/luanti"; exit 1; fi
case "$(basename "$SERVER")" in
	*server*) MODE="" ;;
	*) MODE="--server" ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/games/cmexport" "$TMP/world/worldmods"
# A copy, not a link: Git Bash on Windows cannot make links, and the server must not see later edits.
for item in game.conf settingtypes.txt mods menu; do cp -r "$REPO/$item" "$TMP/games/cmexport/"; done
cp -r "$REPO/tools/cmdump" "$TMP/world/worldmods/cmdump"
printf 'gameid = cmexport\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$TMP/world/world.mt"
# One emerge thread: nothing else asks for map blocks while the museum is built, so none is written over it.
printf 'server_announce = false\nnum_emerge_threads = 1\ncrystalminer.pretest = false\n' > "$TMP/minetest.conf"

TIMEOUT=""
command -v timeout >/dev/null 2>&1 && TIMEOUT="timeout 300"
LUANTI_GAME_PATH="$TMP/games" MINETEST_GAME_PATH="$TMP/games" $TIMEOUT "$SERVER" $MODE \
	--world "$TMP/world" --config "$TMP/minetest.conf" --port 30188 > "$TMP/server.log" 2>&1 || true

if [ ! -f "$TMP/world/museum.json" ]; then
	echo "The museum was not recorded. Server log:"
	grep -v "SHA256" "$TMP/server.log" | tail -30
	exit 1
fi
grep "\[cmdump\]" "$TMP/server.log" | sed 's/.*\[cmdump\] /museum: /'
mkdir -p web/data
cp "$TMP/world/museum.json" web/data/museum.json
echo "web/data/museum.json: $(wc -c < web/data/museum.json) bytes"

# The museum's textures under their game names in web/textures/game/: those the museum lists, and every sign base, side bar and letter (signs are drawn from them, see web/js/signs.js).
OUTT=web/textures/game
rm -rf "$OUTT"
mkdir -p "$OUTT"
SRC=mods/crystalminer/textures
n=0
while read -r name; do
	if [ -n "$name" ] && [ -f "$SRC/$name" ]; then cp "$SRC/$name" "$OUTT/"; n=$((n + 1)); fi
done < "$TMP/world/museum_textures.txt"
for f in "$SRC"/crystalminer_sign_*.png; do cp "$f" "$OUTT/"; n=$((n + 1)); done
for f in "$SRC"/crystalminer_[rbc][0-9]*_[0-9]*.png; do cp "$f" "$OUTT/"; n=$((n + 1)); done
echo "$OUTT: $n textures"
