# crystalminer in the browser

A web version of crystalminer that runs in any modern browser, with nothing to install: the Portal Hall with the Symmetry Gate, all 23 symmetry worlds, the tiers and quizzes, the guides, the Free Lab with its challenges, and Prism, the AI tutor, with its billboard. It is built with [three.js](https://threejs.org) and a small PHP script for the chat, so it runs on ordinary shared web hosting such as Hostinger's.

The science is not rewritten for the web: `tools/export_web.lua` runs the game's own Lua engine and writes every world's symmetry operations, markers, quiz questions, guides and Prism's texts into `data/crystalminer.json`. The browser only applies those operations (`js/symmetry.js`), and `tests/test_web.mjs` checks that it makes exactly the copies the Lua engine does, in every world.

## What is in this folder

| Path | What it is |
|---|---|
| `index.html`, `css/`, `js/` | The game in the browser (three.js is loaded from the jsDelivr CDN) |
| `data/crystalminer.json` | Worlds, operations, markers, lessons and texts, made by `tools/export_web.lua` |
| `textures/` | The game's block textures, guide pictures and Prism's art, copied by the export |
| `api/chat.php` | Prism's chat: adds the grounding text and the API key, asks the model, returns the answer |
| `api/prompt.txt` | Prism's grounding text (the game's lesson text), read only by `chat.php` |
| `api/config.example.php` | A template for the chat's settings |
| `.htaccess`, `api/.htaccess` | Keep the API folder's files, and any key file, from being served |

## Putting it on Hostinger (Premium web hosting)

1. In hPanel open **File Manager** (or connect with SFTP) and upload the **contents** of this `web/` folder into `public_html/`, or into a subfolder such as `public_html/crystalminer/` to have it at `yourdomain/crystalminer/`.
2. Give Prism its key, **outside `public_html`** so the web server can never hand it out. In your home folder (the folder that contains `public_html`), create a file named `.env` with one line:
   ```
   DEEPSEEK_API_KEY=your-key-here
   ```
   `chat.php` looks for `.env` (or `crystalminer-config.php`, from `api/config.example.php`) in its own folder and up to four folders above, so the home folder is found whether the game is in `public_html/` or a subfolder of it.
3. Open the site. Walk to Prism's desk (east side of the Portal Hall) or press **P**, and ask a question.

PHP 8.0 or later with the curl extension is needed; Hostinger's plans have both. No database is used: each player's progress and builds are kept in their own browser.

**Choosing the model.** As in the game, the model is `provider/model`, named as in LiteLLM, with DeepSeek as the default. Add `CRYSTALMINER_TUTOR_MODEL=openai/gpt-...` (or `anthropic/...`, `gemini/...`, `openrouter/<org>/<model>`, `litellm_proxy/<model>`, ...) to the same `.env`, with that provider's key (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, ...). The full list is in the main README, under "The AI tutor".

**Limits and cost.** Each visitor can ask a question every 4 seconds and 60 an hour, and the whole site 2000 a day; change them in `crystalminer-config.php`. Visitors are counted by a hash of their address, in `api/cache/`, which is created on the first question and denied to the web. Pages from other websites cannot use the chat from a browser.

## Trying it on your own computer

The game part needs only a web server (opening `index.html` as a file does not work, because browsers block loading the data that way). The chat needs PHP:

```bash
php -S 127.0.0.1:8080 -t web
```

and then open http://127.0.0.1:8080. `chat.php` finds a `.env` with the key in the folders above `web/api/`, as on the server. Without PHP, `python -m http.server 8080 --directory web` serves everything but the chat.

## After changing the game

Whenever `content.lua`, `guides.lua`, `tutor.lua` or the symmetry engine change, run

```bash
luajit tools/export_web.lua
```

and upload `data/`, `textures/` and `api/prompt.txt` again. `node tests/test_web.mjs` (also run by `tests/run_all.sh` and GitHub Actions) fails if the exported data is out of date.

## Controls

W A S D walk, the mouse looks, Space jumps; K flies (Space up, Shift down), J goes fast. Right-click places a block, left-click removes one or punches a portal. 1 to 8 or the wheel pick a colour; M shows or hides the symmetry markers. G is the guide to where you are, Q the quiz, I the progress board, P asks Prism, H goes back to the Portal Hall, L chooses the Free Lab's symmetry and X works out the symmetry of a build there. Esc pauses.

## Not in the web version yet

The museum's galleries (history, crystal structures and the clue hunt), the Try-it Pad, the visitor tour, step-by-step and by-hand modes, the stereogram, the pre- and post-test and the teacher's class view are only in the Luanti game for now. It is made for a computer with a keyboard and mouse; phones and tablets can open it but cannot move around yet.
