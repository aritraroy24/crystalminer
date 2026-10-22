# crystalminer in the browser

A web version of crystalminer that runs in any modern browser, with nothing to install: the Museum of Crystals and Symmetry as the game builds it (the foyer, the Workshop's Try-it Pad, Visitor information with Prism, the information-desk NPC and the billboard, Gallery 1's Symmetry Gate, Gallery 2's history and its six holograms of the exhibit rooms' structures, Gallery 3's crystal models and clue crystals, the Portal Hall, the six crystal-exhibit rooms and the visitors who walk around the museum), all 23 symmetry worlds, the tiers and quizzes, the guides, and the Free Lab with its challenges. It is built with [three.js](https://threejs.org) and two small PHP scripts, for the chat and for the live crystal structures, so it runs on ordinary shared web hosting such as Hostinger's.

Nothing is rewritten for the web:

- **The museum** is recorded from a real build: `tools/export_museum.sh` starts a headless Luanti server with a small recording mod (`tools/cmdump`), and writes every block (kind and facing), every sign with its lettering, every picture, the portals, clue crystals, levers, NPCs and exhibit rooms into `data/museum.json`. The browser draws the blocks from the game's own block definitions (`js/nodes.js`) and the signs from the game's own letter images (`js/signs.js`), so the museum looks as it does in Luanti.
- **The science** comes from the game's Lua engine: `tools/export_web.lua` writes every world's symmetry operations, markers, quiz questions, guides, the clue questions, the exhibit structures and Prism's texts into `data/crystalminer.json`. The browser only applies those operations (`js/symmetry.js`), and `tests/test_web.mjs` checks that it makes exactly the copies the Lua engine does, in every world.

## What is in this folder

| Path | What it is |
|---|---|
| `index.html`, `css/`, `js/` | The game in the browser (three.js is loaded from the jsDelivr CDN) |
| `data/museum.json` | The museum as the game builds it, recorded by `tools/export_museum.sh` |
| `data/crystalminer.json` | Worlds, operations, markers, lessons, clues, exhibit structures and texts, made by `tools/export_web.lua` |
| `textures/` | Textures for the worlds, guide pictures and Prism's art (`tools/export_web.lua`); `textures/game/` the museum's textures and sign letters under their game names (`tools/export_museum.sh`) |
| `api/chat.php` | Prism's chat: adds the grounding text and the API key, asks the model, returns the answer |
| `api/mp.php` | The crystal-exhibit rooms' live structures: adds the Materials Project key to the game's two lookups, caches the answers |
| `api/common.php` | What both scripts share: settings, keys, limits (not reachable from the web) |
| `api/prompt.txt` | Prism's grounding text (the game's lesson text), read only by `chat.php` |
| `api/config.example.php` | A template for the settings of both scripts |
| `og.jpg` | The link preview picture (1200 x 630), named in `index.html`'s Open Graph tags with the site's address: change those addresses for a copy on another domain |
| `.htaccess`, `api/.htaccess` | Keep the API folder's files, and any key file, from being served |

## Putting it on Hostinger (Premium web hosting)

1. In hPanel open **File Manager** (or connect with SFTP) and upload the **contents** of this `web/` folder into `public_html/`, or into a subfolder such as `public_html/crystalminer/` to have it at `yourdomain/crystalminer/`.
2. Give Prism its key, **outside `public_html`** so the web server can never hand it out. In your home folder (the folder that contains `public_html`), create a file named `.env` with one line:
   ```
   DEEPSEEK_API_KEY=your-key-here
   ```
   For live crystal structures in the exhibit rooms, add a second line with your Materials Project key (free with an account at https://next-gen.materialsproject.org/api):
   ```
   MP_API=your-materials-project-key
   ```
   Both scripts look for `.env` (or `crystalminer-config.php`, from `api/config.example.php`) in its own folder and up to four folders above, so the home folder is found whether the game is in `public_html/` or a subfolder of it.
3. Open the site. You start in the museum's foyer; Prism's desk is in Visitor information, east of the foyer (or press **P** anywhere). Ask a question.

PHP 8.0 or later with the curl extension is needed; Hostinger's plans have both. No database is used: each player's progress and builds are kept in their own browser.

**Choosing the model.** As in the game, the model is `provider/model`, named as in LiteLLM, with DeepSeek as the default. Add `CRYSTALMINER_TUTOR_MODEL=openai/gpt-...` (or `anthropic/...`, `gemini/...`, `openrouter/<org>/<model>`, `litellm_proxy/<model>`, ...) to the same `.env`, with that provider's key (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, ...). The full list is in the main README, under "The AI tutor".

**Limits and cost.** Each visitor can ask a question every 4 seconds and 60 an hour, and the whole site 2000 a day; change them in `crystalminer-config.php`. Visitors are counted by a hash of their address, in `api/cache/`, which is created on the first question and denied to the web. Pages from other websites cannot use the chat from a browser.

**Live crystal structures.** With `MP_API` set, punching one of the six crystal-exhibit portals loads a new random structure from the Materials Project's MPContribs, with the game's loading notice (the search stage and the time so far), and the player enters when it is ready, as in the game: a random element, structures whose name contains it, checked one by one until one is bulk, ordered, small enough for the room and unlike what the other rooms show. The browser does all of that (`js/exhibit_live.js` and `js/exhibit_fetch.js`, ports of the game's Lua, checked against it by the tests); `api/mp.php` only adds the key, and it answers nothing but those two lookups, so the key cannot be used for anything else through the site. It is on whenever a key is set; `'live_exhibits' => false` in `crystalminer-config.php` (or `CRYSTALMINER_LIVE_EXHIBITS=0` in `.env`) turns it off. Answers are cached in `api/cache/` (lists for a day, structures for 30 days), each visitor can make 240 requests an hour and the site 3000 a day to the Materials Project; when a limit is reached, or no structure is found, the room shows the next of the three built-in structures instead, as the game does without a key. Each browser keeps what its rooms show (as the game keeps it in the world), and Gallery 2's holograms show the same structures, as clouds of glowing dust over their pedestals (`js/hologram.js`, from the game's `hologram_logic.lua`). The structures are Materials Project data (CC BY 4.0): each room's panel names the record and MPContribs as its source, so keep that panel if you change the rooms.

## Trying it on your own computer

The game part needs only a web server (opening `index.html` as a file does not work, because browsers block loading the data that way). The chat needs PHP:

```bash
php -S 127.0.0.1:8080 -t web
```

and then open http://127.0.0.1:8080. `chat.php` and `mp.php` find a `.env` with the keys in the folders above `web/api/`, as on the server. Without PHP, `python -m http.server 8080 --directory web` serves everything but the chat and the live structures.

## After changing the game

Whenever `content.lua`, `guides.lua`, `tutor.lua`, the exhibit data or the symmetry engine change, run

```bash
luajit tools/export_web.lua
```

and whenever the museum's building changes (lobby.lua, furniture.lua, museum.lua, exhibits.lua, npc.lua, signs, ...), also run

```bash
tools/export_museum.sh [path-to-luanti]
```

which needs Luanti (it builds a fresh world on a headless server, about half a minute), then upload `data/`, `textures/` and `api/prompt.txt` again. `node tests/test_web.mjs` (also run by `tests/run_all.sh` and GitHub Actions) fails if `crystalminer.json` is out of date, and checks `museum.json`: a clean build, a portal for every world and exhibit room, every clue crystal's question, every door's two halves, the Try-it Pad's levers, and that every texture the museum draws is there.

## Controls

W A S D walk, the mouse looks, Space jumps; K flies (Space up, Shift down), J goes fast. Right-click places a block, left-click removes one or punches a portal, a door, a clue crystal, a lever or Prism's screen. 1 to 8 or the wheel pick a colour; M shows or hides the symmetry markers. G is the guide to where you are, Q the quiz, I the progress board, P asks Prism, H goes back to the Portal Hall, L chooses the Free Lab's symmetry and X works out the symmetry of a build there. Esc pauses.

## Not in the web version yet

The visitor tour, step-by-step and by-hand modes, the stereogram, the pre- and post-test and the teacher's class view are only in the Luanti game for now. The symmetry worlds are simplified: their build spaces and markers are the game's, their architecture is not yet. It is made for a computer with a keyboard and mouse; phones and tablets can open it but cannot move around yet.
