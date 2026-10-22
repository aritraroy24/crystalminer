# crystalminer: a guide for teachers

crystalminer is a free Luanti game about symmetry, the foundation of crystallography. Students
build inside "worlds" that copy every block they place by a symmetry: a mirror, a turn, a screw
axis and so on. It is written for first-time players of about 12 and up. No crystallography
background is needed, for students or for you.

## What it teaches

Students climb five tiers. Answering every `/quiz` question of a tier opens the next one.
Worlds above a student's tier can be visited, but not built in.

| Tier | Name in the game | Places | Idea |
|---|---|---|---|
| 0 | Symmetry Gate | Gallery 1 (the Gate), Try-it Pad | The four basic moves: translation, rotation, reflection, inversion; left and right hands |
| 1 | Single operations | Mirror Plaza (m), Twofold Yard (2), Fourfold Tower (4), Inversion Core (-1), Translation Hall (P1) | One operation at a time |
| 2 | Combining operations | Twin Mirrors (mm2), Monoclinic Cube (2/m), Square Court (4mm), Orthorhombic Cube (mmm) | Two operations together create new ones |
| 3 | Three dimensions | Diagonal Cube (3), Rotoinversion Room (-4), Bar-Three Room (-3), Kaleidoscope (m-3m), Impossible Room | Cubic symmetry; why crystals cannot have 5-fold axes |
| 4 | Lattices and space groups | Screw Hall (P2_1), Glide Hall (Pa), Spiral Tower (P4_1), Mystery Lab, Free Lab; Pattern Garden: pmm, pgg, p4, p4g | Screw axes, glide planes, flat repeating patterns, naming a hidden symmetry |

Every world's board ends with one real-world example (a molecule, a mineral or a pattern with that
symmetry). The sources for these are listed at the end of this guide.

## A 45-minute lesson

Suggested timings; adjust them to your class.

1. **Foyer (5 min).** Students arrive in the museum foyer. Read the big board together. `/spawn`
   brings anyone who gets lost back here.
2. **Gallery 1 and its quiz (10 min).** Four displays, A to D, each show a shape and a copy made
   by one move. Students compare them, then type `/quiz`. Answering all five questions opens
   tier 1.
3. **Try-it Pad (5 min).** In the Workshop, students build a small lopsided shape, hit a lever
   (T, R, M, I) and predict whether the copy could be turned to match their shape. Good discussion
   point: why do M and I give a "mirror twin" like a left and a right hand? The Pad is shared, so
   let students take turns.
4. **Portal Hall (2 min).** One portal per world, ordered by tier. Punching (left-clicking) a portal
   travels there; the portal behind you in each world comes back.
5. **Two tier-1 worlds (15 min).** For example Mirror Plaza, then Fourfold Tower. Each world's first
   block asks students to predict how many blocks there will be. `/step` shows the copies one at a
   time; `/quiz` asks about the world.
6. **Crystal Museum (5 min).** In Gallery 3, real crystal structures (copper, iron, rock salt,
   caesium chloride, perovskite, diamond) are built one block per atom. Each has a gold clue
   crystal in front of it: punch it to answer a question. `/hunt` lists which are solved.
7. **Wrap-up (3 min).** Open `/class` to see where everyone got to.

For a short demonstration instead (open days, a first lesson), `/tour` is a ten-minute guided
route with a panel at each stop; anyone can use it, and visitors may build at its stops whatever
their tier.

## Commands you need

Teacher commands need the `teacher` privilege. In single player you have it automatically. On a
server, the player who started it (with Host Server) has every privilege; give it to a colleague
with `/grant <name> teacher`.

| Command | Who | What it does |
|---|---|---|
| `/class` | teacher | A table of every student: tier, questions answered, pre- and post-test scores, predictions right, clue crystals found, online |
| `/settier <0-4> [player]` | teacher | Set a student's tier (your own if no name is given), e.g. to skip ahead for a demonstration |
| `/showcase [region \| clear]` | teacher | Fill the worlds with example builds (a butterfly, a windmill, a 48-fold star, ...), or empty them again. `clear` also removes what students built there |
| `/exportdata` | teacher | Save test answers, predictions and discoveries, without names, as three CSV files in the world folder |
| `/tour` | everyone | The ten-minute guided tour (`/tour next`, `/tour back`, `/tour end`) |
| `/quiz`, `/explain`, `/step`, `/hunt`, `/spawn`, `/goto <region>` | everyone | Quiz questions, the guide again, copies one at a time, clue crystals, back to the foyer, travel |

Students can also press **I** for their progress board, **K** to fly and **T** to type a command.

## Hosting a class

1. Install Luanti and crystalminer on your computer and on every student computer (see the README).
   Using the same Luanti version everywhere avoids connection problems.
2. Create the world before the lesson: the first start builds the museum and all the worlds, which
   takes about half a minute.
3. In Luanti's main menu, select crystalminer and your world, tick **Host Server**, and start.
   The port shown there (30000 unless you change it) is the one students need.
4. Students open the **Join Game** tab, type your computer's IP address and the port, choose a
   name and connect. Your computer and theirs must be on the same network, and a firewall may need
   to allow Luanti.
5. Ask students to use a name that is not their full real name.

## The pre- and post-test

New players are offered 11 short questions before they start, and the same ones again when they
reach the top tier (`/pretest`, `/posttest`; turn this off with the setting
`crystalminer.pretest`). Each question has an "I don't know" option. Answers are stored with an
anonymous id. `/class` shows each student's scores and the class's mean normalized gain;
`/exportdata` saves the answers, predictions and discoveries as CSV files without names.

**Ethics.** If you publish such data as research, you need your institution's ethics approval and
informed consent; the notice in the game is not a substitute.

## Known limitations

- The game has been played by its developers but **not yet by students**, and the learning check
  has not yet produced data. We make no claims about learning outcomes.
- The first start of a new world takes about half a minute.
- The AI tutor, Prism (`/ask`, or the information desk), needs an API key for a hosted model
  (DeepSeek by default, or Claude and others) or a free open-source model on your own computer (see
  "The AI tutor" in the README). We have run it only with a local open model; DeepSeek and Claude
  have not been run live by us. Prism's billboard in Visitor information shows every student's
  latest question, without the name, to everyone in the room.
- The Free Lab's symmetry is shared by everyone on the server and resets when the server restarts.
  The Try-it Pad is also shared: students take turns.
- Worlds made with an earlier version are rebuilt on start; blocks built there before are not
  carried over, but tiers and answers are kept.

## Sources for the real-world examples

| World | Example | Source |
|---|---|---|
| Mirror Plaza (m) | methanol, point group Cs = m | https://www.cup.uni-muenchen.de/ch/compchem/geom/sym_Cs.html |
| Twofold Yard (2) | hydrogen peroxide, C2 = 2 | https://chemtube3d.com/SymHOOHC2/ |
| Fourfold Tower (4) | pinnoite, class 4 | https://en.wikipedia.org/wiki/Pinnoite |
| Inversion Core (-1) | kyanite, class -1 (P-1) | https://en.wikipedia.org/wiki/Kyanite |
| Translation Hall (P1) | salt is a unit cell repeated by translations | https://en.wikipedia.org/wiki/Crystal_structure |
| Twin Mirrors (mm2) | water, C2v = mm2 | https://chem.libretexts.org/Courses/University_of_California_Davis/Chem_124A%3A_Fundamentals_of_Inorganic_Chemistry/06%3A_Larger_(Polyatomic)_Molecules/6.03%3A_H2O |
| Monoclinic Cube (2/m) | gypsum, class 2/m | https://en.wikipedia.org/wiki/Gypsum |
| Square Court (4mm) | bromine pentafluoride, C4v = 4mm | https://en.wikipedia.org/wiki/Bromine_pentafluoride |
| Orthorhombic Cube (mmm) | olivine (forsterite), class mmm | https://en.wikipedia.org/wiki/Forsterite |
| Diagonal Cube (3) | methane: a 3-fold axis along each C-H bond | https://l4labs.soton.ac.uk/tutorials/gt/c3a.htm |
| Rotoinversion Room (-4) | chalcopyrite, class -42m | https://en.wikipedia.org/wiki/Chalcopyrite |
| Bar-Three Room (-3) | dolomite, class -3 (R-3) | https://en.wikipedia.org/wiki/Dolomite_(mineral) |
| Kaleidoscope (m-3m) | halite, class m-3m, cubic habit | https://en.wikipedia.org/wiki/Halite |
| Impossible Room | snowflakes: six-fold because ice is hexagonal | https://en.wikipedia.org/wiki/Snowflake |
| Screw Hall (P2_1) | sucrose, P2_1; P2_1 2_1 2_1 is about 30% of protein crystals | https://en.wikipedia.org/wiki/Sucrose, https://people.mbi.ucla.edu/yeates/old_space_group_freq.html |
| Glide Hall (Pa) | footprints on a beach | https://en.wikipedia.org/wiki/Glide_reflection |
| Spiral Tower (P4_1) | lysozyme, P4_3 2_1 2; 4_1 and 4_3 are enantiomorphs | https://www.rcsb.org/experimental/1VDS, https://faculty.washington.edu/stenkamp/bstr515/sasym.html |
| Mirror Tiles (pmm) | stack-bond brickwork | https://www.researchgate.net/publication/225119937_Teaching_Mathematics_through_Brick_Patterns |
| Glide Tiles (pgg) | herringbone floor | https://en.wikipedia.org/wiki/Herringbone_pattern |
| Pinwheel Tiles (p4) | Pythagorean (pinwheel) tiling | https://en.wikipedia.org/wiki/Pythagorean_tiling |
| Weave Tiles (p4g) | Escher's angels and devils, sketch 45 | https://eschermath.org/wiki/Wallpaper_Patterns.html |

Schoenflies to Hermann-Mauguin symbols: https://en.wikipedia.org/wiki/Crystallographic_point_group
