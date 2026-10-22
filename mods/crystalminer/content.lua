-- crystalminer learning content.
--
-- Everything players read lives here, so teachers can edit it without touching code.
-- Generators use Jones notation in crystal axes: x east, y north, z up.
-- "at" is the minimum node corner of a region in world coordinates (the ground surface is y = 0).
--
-- Each region has:
--   showcase: an example build for demonstrations (/showcase): blocks { dx, dy, dz, colour } and
--            pixel art, as offsets from the region's minimum corner. Only this seed is placed;
--            the region's symmetry makes every copy.
--   style:   its architecture (plaza, yard, tower, cube, hall, room, garden); see decor.lua.
--   explain: lines per tier. A player sees the lines for every tier up to their own.
--   quiz:    questions per tier (answer is the 0-based index of the correct option).
--            Reaching tier N+1 needs every tier-N question answered.

return {
	tiers = {
		[0] = "Symmetry Gate",
		[1] = "Single operations",
		[2] = "Combining operations",
		[3] = "Three dimensions",
		[4] = "Lattices and space groups",
	},
	intro = {
		"Welcome to the Museum of Crystals and Symmetry!",
		"Start in the foyer (type /spawn to go there): read the big board, then walk through the door into Gallery 1.",
		"Walk with W A S D, look with the mouse. Press T to type a command, such as /tour for a ten-minute guided tour.",
	},
	glossary = {
		"Symmetry operation: a move that leaves an object indistinguishable from how it started.",
		"Symmetry element: the point, line or plane an operation acts about (centre, axis, mirror plane).",
		"n-fold rotation axis: rotating by 360/n degrees leaves the object unchanged. Written n (2, 3, 4, 6).",
		"Mirror plane: written m. It swaps left- and right-handed shapes.",
		"Inversion centre: written -1 (say 'bar one'). Sends (x, y, z) to (-x, -y, -z).",
		"Rotoinversion: a rotation followed by an inversion, written -n (-1, -3, -4, -6). A mirror is the same as -2.",
		"Point group: the set of all symmetry operations of an object that leave one point fixed.",
		"Order of a group: how many operations it contains. One block in a general position makes that many copies.",
		"Hermann-Mauguin symbol: the standard short name of a group, such as 4mm or 2/m. '/' means 'with a mirror perpendicular to'.",
		"Lattice: an infinite array of points, each with identical surroundings. A crystal is a motif repeated on a lattice.",
		"Unit cell: the repeating box of a crystal. Copying it along the lattice translations fills space.",
		"Screw axis: rotate, then translate along the axis. 2_1 means a half turn plus half a cell.",
		"Glide plane: reflect, then translate parallel to the plane by a fraction of a lattice translation, usually half a cell edge.",
		"Crystallographic restriction: a lattice can only have 1-, 2-, 3-, 4- or 6-fold rotation axes. 5-fold and 7-fold or higher are impossible in a periodic crystal.",
		"There are exactly 32 crystallographic point groups. 25 of them fit a cubic block grid; the 7 hexagonal ones need a 6-fold or -6 axis, which a square grid does not have.",
		"Plane group: the symmetry of a repeating pattern on a flat surface, such as a tiled floor. There are exactly 17. 12 of them fit a square block grid; the other 5 need 3-fold or 6-fold rotations.",
		"Chiral: a shape that cannot be moved to match its own mirror image, like a hand. An achiral shape has a mirror plane or an inversion centre of its own.",
		"Quasicrystals (discovered by Dan Shechtman, Nobel Prize in Chemistry 2011) show 5-fold symmetry in diffraction because they are ordered but not periodic.",
	},
	-- The same short test before and after playing, to measure what the game teaches. Some items
	-- ask about things the game never shows directly (a 6-fold axis), to test transfer rather
	-- than recall. Each item's last option is "I don't know yet", which counts as not correct.
	-- tag: the idea or common difficulty the item probes.
	assessment = {
		intro = {
			"Before you start: 11 quick questions, to see what you already know.",
			"This is not a test of you, and nobody expects you to know the answers yet. Many of the words "
				.. "will be new: that is fine, the museum explains them.",
			"If you are not sure, choose 'I don't know yet' instead of guessing. At the end you get the same "
				.. "questions again, so you can see how much you have learned.",
			"Your answers are saved without your name.",
		},
		post_intro = {
			"You have reached the top tier. Here are the 11 questions from the start again.",
			"Answer them as well as you can now. Your answers are saved without your name.",
		},
		-- Plain wording for first-time players: each item explains its key word without giving the
		-- answer away. The ids, options and answers are those of the earlier wording.
		items = {
			{
				id = "order4", tag = "group order",
				q = "Imagine a machine that copies every block you place, each time turning it a quarter of a full "
					.. "turn around a pole, until the copies come back to where they started. You place one block a "
					.. "few steps away from the pole. How many blocks are there in the end, counting yours?",
				options = { "1", "2", "4", "8", "I don't know yet" }, answer = 2,
			},
			{
				id = "order6", tag = "group order (transfer)",
				q = "Now the machine turns each copy one sixth of a full turn around the pole instead. One block a few "
					.. "steps from the pole: how many blocks in the end, counting yours?",
				options = { "2", "3", "6", "12", "I don't know yet" }, answer = 2,
			},
			{
				id = "on_element", tag = "site on a symmetry element",
				q = "A mirror runs through a room like an invisible glass wall, copying every block to its other side. "
					.. "You place a block exactly in the mirror, so that the mirror cuts it in half. How many blocks "
					.. "do you see, counting yours?",
				options = { "1", "2", "I don't know yet" }, answer = 0,
			},
			{
				id = "handedness", tag = "handedness",
				q = "Which of these moves can turn a left hand into a right hand?",
				options = { "Turning it (a rotation)", "Sliding it (a translation)", "Mirroring it (a reflection)",
					"None of these", "I don't know yet" }, answer = 2,
			},
			{
				id = "inversion", tag = "inversion",
				q = "'Inversion' sends a block in a straight line through a centre point, to the same distance on the "
					.. "other side. A block is 2 steps east of the centre and 3 steps above it. Where does its copy go?",
				options = { "2 west and 3 up", "2 west and 3 down", "2 east and 3 down", "I don't know yet" }, answer = 1,
			},
			{
				id = "combine_mm", tag = "combining operations",
				q = "Two mirror walls meet at a right angle, like the corner of a room. Besides the two mirrors, "
					.. "what other symmetry does this corner have?",
				options = { "A half turn about the line where the mirrors meet", "A quarter turn about that line",
					"A trip through a centre point (an inversion)", "Nothing else", "I don't know yet" }, answer = 0,
			},
			{
				id = "rotoinversion", tag = "rotoinversion",
				q = "A shape stays the same under a two-step move called '-4' (say 'bar four'): first a quarter turn, "
					.. "then a trip through its centre point. It has no other symmetry. Does the quarter turn on its "
					.. "own, without the second step, leave the shape the same?",
				options = { "Yes", "No", "I don't know yet" }, answer = 1,
			},
			{
				id = "restriction", tag = "crystallographic restriction",
				q = "A crystal is one small pattern repeated in rows, with no gaps, in every direction. Could a crystal "
					.. "have 5-fold symmetry, that is, look exactly the same after one fifth of a turn?",
				options = { "Yes", "No", "Only cubic crystals", "I don't know yet" }, answer = 1,
			},
			{
				id = "screw", tag = "screw axis",
				q = "Crystals can have a symmetry named after the thread of a screw, called a screw axis. What does a "
					.. "'2_1' screw axis (say 'two-one') do to a block?",
				options = { "Turns it half a turn", "Turns it half a turn and moves it half a repeat along the axis",
					"Mirrors it and moves it half a repeat", "I don't know yet" }, answer = 1,
			},
			{
				id = "glide", tag = "glide plane",
				q = "Crystals can also have a symmetry called a glide plane. What does a glide plane do to a block?",
				options = { "Mirrors it, then slides it along the mirror by part of a repeat (usually half)",
					"Turns it, then slides it along the turning axis", "Mirrors it twice", "I don't know yet" }, answer = 0,
			},
			{
				id = "lattice_cscl", tag = "lattice versus structure",
				q = "In caesium chloride, chloride ions (charged chlorine atoms) sit at the 8 corners of each tiny cube, "
					.. "and a caesium ion sits at its centre. Crystallographers call a pattern 'body-centred' only if the centre is exactly "
					.. "like the corners. Is caesium chloride body-centred?",
				options = { "Yes, there is an ion at the centre", "No: the ion at the centre is a different kind",
					"I don't know yet" }, answer = 1,
			},
		},
	},
	-- /quiz in a place whose questions for the player's tier are all answered (or that only has
	-- questions of lower tiers) asks one of that place's questions again, as a review.
	quiz_review = {
		label = "Review question: answering it does not change your tier.",
		correct = "That was a review question, so your tier stays the same. Type /quiz for another one.",
		elsewhere = "The questions for your tier are in other places: press I to see where.",
	},
	gate = {
		id = "symmetry_gate",
		name = "Symmetry Gate",
		at = { -25, 1, -25 },
		quiz = {
			[0] = {
				{
					q = "Display A shows a shape and its copy. Which operation made the copy?",
					display = "A",
					hint = "Is the copy the same way round as the original, or a mirror image of it?",
					options = { "Translation", "Rotation", "Reflection", "Inversion" },
					answer = 2,
					why = "The copy is a mirror image: left and right are swapped, which no rotation can do.",
				},
				{
					q = "Display B: which operation made the copy?",
					display = "B",
					hint = "Walk around the display. Could you turn the original to match the copy without lifting it off the floor?",
					options = { "Translation", "Rotation", "Reflection", "Inversion" },
					answer = 1,
					why = "The copy is the shape turned half a turn (180 degrees) about a vertical axis.",
				},
				{
					q = "Display C: which operation made the copy?",
					display = "C",
					hint = "Compare the two shapes: is anything turned or swapped, or is the copy just somewhere else?",
					options = { "Translation", "Rotation", "Reflection", "Inversion" },
					answer = 0,
					why = "The copy is the same shape, the same way round, just moved along a line.",
				},
				{
					q = "Display D: which operation made the copy?",
					display = "D",
					hint = "Is the copy upside down? Which way does each part point compared with the original?",
					options = { "Translation", "Rotation", "Reflection", "Inversion" },
					answer = 3,
					why = "Every block went through the centre point to the opposite side: up became down, east became west, north became south.",
				},
				{
					q = "Which operation turns a left hand into a right hand?",
					hint = "Hold your hands up to a mirror. Which hand looks back at you?",
					options = { "Translation", "Rotation", "Reflection" },
					answer = 2,
					why = "Reflection reverses handedness. Translations and rotations never do.",
				},
			},
		},
	},
	-- Tier 0 station: build a shape, punch a lever, predict whether the result matches.
	tryit = {
		id = "tryit_pad",
		name = "Try-it Pad",
		at = { -50, 1, -46 },
		explain = {
			"Build any shape in the glass box on the left. Then punch a lever: T translates, R rotates, M mirrors, I inverts.",
			"Before you see the result, predict: could your shape be moved, without mirroring it, to match the result?",
			"Try it with a lopsided shape and with a symmetric one. Do mirrors always change a shape?",
		},
	},
	-- The Crystal Museum: real crystal structures built exactly on the block grid, one block per
	-- atom with a gap between (scale 2). Neighbour counts in the facts and clue answers are checked
	-- against the models in tests/test_museum.lua. Each exhibit has a clue crystal in front of it
	-- (the scavenger hunt): punch it for a question; a right answer counts as a discovery.
	museum = {
		id = "crystal_museum",
		name = "Crystal Museum",
		at = { -14, 1, -3 },
		size = { 74, 20, 62 },
		intro = {
			"Real crystals, one block per atom. Fly around them and look along their rows and diagonals.",
			"Each exhibit has a glowing gold clue crystal in front of it: punch it to answer a question about that crystal.",
			"Many crystals share the cube's point group m-3m, yet their atoms are arranged differently. "
				.. "The space group tells them apart: it adds the lattice and the screw axes and glide planes.",
		},
		exhibits = {
			{
				id = "copper", name = "Copper", structure = "fcc", n = 6, colours = { cu = "orange" },
				label = "Copper: face-centred cubic, Fm-3m",
				facts = {
					"Copper: atoms at the corners and the face centres of every cubic cell. This is called face-centred cubic.",
					"Each atom touches 12 others: one of the two closest ways to pack equal spheres. Space group Fm-3m.",
				},
				clue = {
					q = "How many nearest neighbours does each copper atom have?",
					options = { "6", "8", "12", "4" }, answer = 2,
					why = "12: four in its own layer of the cube face, four above and four below.",
					check = { centre = "cu", expected = 12 },
				},
			},
			{
				id = "iron", name = "Iron", structure = "bcc", n = 6, colours = { fe = "light_grey" },
				label = "Iron: body-centred cubic, Im-3m",
				facts = {
					"Iron at room temperature: atoms at the corners and at the centre of every cubic cell. This is called body-centred cubic.",
					"Each atom has 8 nearest neighbours, along the cube diagonals. Space group Im-3m.",
				},
				clue = {
					q = "How many nearest neighbours does each iron atom have?",
					options = { "6", "8", "12", "4" }, answer = 1,
					why = "8: the corners of the cube around it, along the four cube diagonals.",
					check = { centre = "fe", expected = 8 },
				},
			},
			{
				id = "rocksalt", name = "Rock salt", structure = "rocksalt", n = 6, colours = { na = "purple", cl = "lime" },
				label = "Rock salt NaCl: purple Na, green Cl, Fm-3m",
				facts = {
					"Rock salt, sodium chloride: sodium (purple) and chloride (green) alternate along every row, in all three directions.",
					"Each ion has 6 neighbours of the other kind. Space group Fm-3m: the lattice is face-centred cubic, like copper's.",
				},
				clue = {
					q = "How many chloride ions surround each sodium ion?",
					options = { "4", "6", "8", "12" }, answer = 1,
					why = "6: one in each direction, east, west, north, south, up and down.",
					check = { centre = "na", around = { "cl" }, expected = 6 },
				},
			},
			{
				id = "cscl", name = "Caesium chloride", structure = "cscl", n = 6, colours = { cs = "light_blue", cl = "lime" },
				label = "Caesium chloride: blue Cs, green Cl, Pm-3m",
				facts = {
					"Caesium chloride: chloride (green) at the cube corners, caesium (blue) at the cube centre.",
					"It looks body-centred, but the centre holds a different ion, so the lattice is primitive cubic: space group Pm-3m.",
				},
				clue = {
					q = "How many chloride ions surround each caesium ion?",
					options = { "4", "6", "8", "12" }, answer = 2,
					why = "8, at the corners of the cube around it.",
					check = { centre = "cs", around = { "cl" }, expected = 8 },
				},
			},
			{
				id = "perovskite", name = "Perovskite", structure = "perovskite", n = 6,
				colours = { sr = "green", ti = "white", o = "red" },
				label = "Strontium titanate (perovskite): green Sr, white Ti, red O, Pm-3m",
				facts = {
					"Strontium titanate: titanium (white) at the cube centre, oxygen (red) at the face centres, strontium (green) at the corners.",
					"Each titanium sits inside an octahedron of 6 oxygens. Many materials share this arrangement, called the perovskite structure. Space group Pm-3m.",
				},
				clue = {
					q = "How many oxygen atoms surround each titanium atom?",
					options = { "4", "6", "8", "12" }, answer = 1,
					why = "6, at the corners of an octahedron: one on each face of the cube around the titanium.",
					check = { centre = "ti", around = { "o" }, expected = 6 },
				},
			},
			{
				id = "diamond", name = "Diamond", structure = "diamond", n = 8, colours = { c = "black" },
				label = "Diamond: Fd-3m",
				facts = {
					"Diamond: every carbon atom bonds to 4 others at the corners of a tetrahedron.",
					"Space group Fd-3m. The point symmetry at each carbon atom is -43m, the symmetry of a tetrahedron.",
				},
				clue = {
					q = "How many neighbours does each carbon atom in diamond have?",
					options = { "3", "4", "6", "8" }, answer = 1,
					why = "4, at the corners of a tetrahedron. Strong bonds running in every direction through the crystal are why diamond is so hard.",
					check = { centre = "c", expected = 4 },
				},
			},
		},
	},
	-- Prism, the AI tutor at the information desk (tutor_window.lua). The model's answers are grounded in this file (tutor.lua); the words of the window itself are here.
	tutor = {
		name = "Prism",
		role = "the crystal tutor",
		welcome = "Hi %s! I'm **Prism**. Ask me anything about symmetry, crystals or this museum: "
			.. "what a mirror plane is, why no crystal has a fivefold axis, how a screw axis works. "
			.. "Pick a question below or type your own.",
		about = "Ask me about symmetry, crystals and this museum. I remember our chat until you start a new one.",
		disclaimer = "I answer from the museum's own lesson text, but I can still be wrong. If something "
			.. "looks odd, check it in the game or ask your teacher.",
		off = "I'm asleep: the AI tutor isn't set up on this server yet. Teachers: see \"The AI tutor\" in the README.",
		thinking = "Prism is thinking...",
		-- Suggested questions, by tier, each at most 23 characters to fit its button; in a world the first is replaced by one about that world.
		here = "Explain this world",
		suggestions = {
			[0] = { "What is symmetry?", "Mirror or inversion?", "Why do crystals repeat?" },
			[1] = { "What is a twofold axis?", "What is inversion?", "What is a lattice?" },
			[2] = { "How do mirrors combine?", "What does 2/m mean?", "What is a point group?" },
			[3] = { "Why no fivefold axis?", "What is rotoinversion?", "Why 48 copies in m-3m?" },
			[4] = { "What is a screw axis?", "Glide plane vs mirror?", "What is a space group?" },
		},
		desk = "# ASK PRISM, THE AI TUTOR\nRight-click the screen, or type /ask anywhere",
		-- The pixel billboard on the east wall of Visitor information (billboard.lua). It shows the latest question to everyone in the room, so it never shows who asked.
		board = {
			title = "PRISM · LIVE",
			hint = "right-click me or type /ask",
			welcome = "Hi! I'm **Prism**, the crystal tutor of this museum. Ask me anything about symmetry and crystals.",
			how = "Right-click this screen or the screen on the desk, or type /ask anywhere. The latest question and my answer appear here.",
			fact_title = "WORDS TO KNOW",
			asked = "A VISITOR ASKED:",
			answer = "PRISM:",
			thinking = "thinking...",
			more = "... the rest is in the chat: right-click me or type /ask",
		},
	},
	-- The Museum of Crystals and Symmetry: the lobby where everyone starts (after the central hall
	-- of MolCraft). Rooms and their positions are in lobby.lua; the words on every sign are here.
	-- In sign texts, a line starting with "# " is a heading.
	lobby = {
		spawn = { x = 0, y = 1, z = -44 },
		welcome = "# Museum of Crystals and Symmetry\n"
			.. "Crystals are atoms arranged in patterns that repeat. Symmetry is the language that describes those patterns, "
			.. "and this museum teaches it by letting you build with it.\n\n"
			.. "West: the Workshop, with the Try-it Pad.   East: Visitor information, with Prism, the AI tutor.\n"
			.. "North: Gallery 1, Four kinds of symmetry. Beyond it, Gallery 2, A history of crystallography, "
			.. "and Gallery 3, Crystals at the atomic scale.\n"
			.. "Furthest north: the Portal Hall, with a portal to every symmetry world.\n\n"
			.. "Type /tour for a ten-minute guided tour. Press I for your progress.",
		information = "# How to explore\n"
			.. "Walk with W A S D and look with the mouse. Press K to fly and J to go fast.\n"
			.. "Press T or / to type a command, I for your progress board.\n\n"
			.. "/quiz answers questions that unlock the next tier.\n"
			.. "/explain repeats what the place you are in is about.\n"
			.. "/step shows each copy appear, with the name of the operation.\n"
			.. "/byhand lets you place the copies yourself.\n"
			.. "/whatsymmetry works out the symmetry of what you built.\n"
			.. "/tour is a ten-minute guided tour.\n\n"
			.. "Every block in your inventory is free.",
		workshop = "# The Workshop: the Try-it Pad\n"
			.. "Build any shape in the glass box marked Your shape. Then punch a lever: T translates it, R turns it half a turn, "
			.. "M mirrors it and I inverts it through the centre.\n\n"
			.. "Before you look, predict: could the result be moved, without mirroring it, to match your shape? "
			.. "Try it with a lopsided shape, then with a symmetric one.",
		gallery1 = "# Four kinds of symmetry\n"
			.. "A symmetry operation moves an object so that it looks exactly the same afterwards.\n\n"
			.. "Each display shows a shape on the left and, on the right, its copy made by one operation: "
			.. "a translation, a rotation, a reflection or an inversion. Which is which?\n\n"
			.. "Stand in front of the displays and type /quiz to answer. "
			.. "Answering them all opens the first symmetry worlds in the Portal Hall.",
		display = "# Display %s\nWhich operation made the copy on the right? Type /quiz.",
		gallery2 = "# A history of crystallography\n"
			.. "For three centuries, people have asked why crystals have flat faces and sharp angles. "
			.. "The answer, symmetry and the repeating lattice, grew step by step. Walk along the timeline.",
		gallery3 = "# Crystals at the atomic scale\n"
			.. "Each model is a real crystal, one block per atom, with a gap between atoms so you can see inside.\n\n"
			.. "Many of them share the cube's point group m-3m, yet their atoms are arranged differently: "
			.. "the space group tells them apart.\n\n"
			.. "Punch the gold clue crystal in front of each model to answer a question about it.",
		portals = "# The Portal Hall\n"
			.. "Each portal leads to a world with one symmetry group. Whatever you build there is copied by every operation "
			.. "of the group.\n\n"
			.. "Tier 1: one operation at a time.  Tier 2: combining operations.  Tier 3: three dimensions.  "
			.. "Tier 4: lattices, space groups and floor patterns.\n\n"
			.. "Worlds above your tier can be visited but not built in. Punch a portal to travel; "
			.. "every world has a portal back.",
		history = {
			{ year = "1669", who = "Nicolas Steno",
				text = "Studying quartz, Steno found that the angles between matching faces are always the same, however "
					.. "large or misshapen the crystal: the first law of crystallography." },
			{ year = "1784", who = "René-Just Haüy",
				text = "Haüy proposed that crystals are built from tiny identical units stacked in rows, which explained why "
					.. "calcite always breaks into smaller rhombohedra: the first idea of a unit cell." },
			{ year = "1830", who = "Johann Hessel",
				text = "Hessel showed that the outward shapes of crystals can have only 32 kinds of symmetry: the 32 crystal "
					.. "classes, or point groups. 25 of them fit the block grid of this world." },
			{ year = "1848", who = "Auguste Bravais",
				text = "Bravais showed that there are exactly 14 different kinds of lattice in three dimensions, now called "
					.. "the Bravais lattices." },
			{ year = "1891", who = "Evgraf Fedorov and Arthur Schoenflies",
				text = "Working independently, they counted every way that symmetry operations and lattices can combine "
					.. "in three dimensions: 230 space groups." },
			{ year = "1912", who = "Max von Laue",
				text = "With Walter Friedrich and Paul Knipping, Laue shone X-rays through a crystal and recorded a pattern of "
					.. "spots, showing that crystals are regular arrays of atoms. Nobel Prize in Physics, 1914." },
			{ year = "1913", who = "William Henry Bragg and William Lawrence Bragg",
				text = "Father and son used X-ray diffraction to work out the first crystal structures, among them rock salt "
					.. "and diamond. Nobel Prize in Physics, 1915." },
			{ year = "1935", who = "The International Tables",
				text = "The first International Tables for crystallography were published, using the Hermann-Mauguin "
					.. "symbols, such as 4mm and m-3m, that this museum uses." },
			{ year = "1953", who = "The double helix of DNA",
				text = "X-ray images of DNA, including Photo 51 by Rosalind Franklin and Raymond Gosling, helped James Watson "
					.. "and Francis Crick propose the double helix. A helix has screw symmetry." },
			{ year = "1964", who = "Dorothy Crowfoot Hodgkin",
				text = "Nobel Prize in Chemistry for using X-ray crystallography to work out the structures of important "
					.. "molecules, including penicillin and vitamin B12." },
			{ year = "1982", who = "Dan Shechtman",
				text = "Shechtman saw a diffraction pattern with 5-fold symmetry, which no periodic crystal can have. "
					.. "Quasicrystals are ordered but not periodic. Nobel Prize in Chemistry, 2011." },
			{ year = "2014", who = "International Year of Crystallography",
				text = "UNESCO's International Year of Crystallography marked a century of X-ray crystallography." },
		},
	},
	-- The boards on the arrival plaza of every symmetry world.
	worlds = {
		howto = "# What to do here\n"
			.. "Walk through the gate. Place a block anywhere inside the region and watch its copies appear. "
			.. "Your first block asks you to predict how many there will be.\n\n"
			.. "/step: watch the copies appear one at a time, each named.\n"
			.. "/byhand: place the copies yourself; each one is checked.\n"
			.. "/whatsymmetry: the exact symmetry of what you built.\n"
			.. "/quiz: questions about this world.\n"
			.. "/elements: choose which symmetry markers to show.\n\n"
			.. "Markers: a lens is a 2-fold axis, a triangle 3-fold, a square 4-fold. Sheets of blue dots are "
			.. "mirror planes; a white disc is an inversion centre. The round diagram in the corner of the screen "
			.. "is the stereogram of this world's symmetry.",
		locked = "Building here opens at tier %d. You reach a new tier by answering all the /quiz questions of "
			.. "the places you have already opened. Press I to see your tier.",
	},
	-- The visitor tour: about ten minutes, for museums and open days (/tour).
	tour = {
		{
			at = "symmetry_gate", title = "What is symmetry?",
			text = "A symmetry operation is a move that leaves an object looking the same. The four displays show the four kinds: reflection, rotation, translation and inversion.",
		},
		{
			at = "tryit_pad", title = "Left and right hands",
			text = "Build a lopsided shape in the box, punch lever M and predict: can the mirror image be turned to match your shape?",
		},
		{
			at = "mirror_plaza", title = "A mirror builds with you",
			text = "Place a few blocks on one side: the mirror finishes your build. Notice that it swaps left and right.",
		},
		{
			at = "kaleidoscope", title = "The symmetry of a cube",
			text = "One block here becomes 48: every rotation of a cube, and every one of those mirrored. Copper, iron and rock salt have this symmetry.",
		},
		{
			at = "impossible_room", title = "What crystals cannot do",
			text = "A crystal repeats in rows, and rows only allow 2-, 3-, 4- and 6-fold rotations. A 5-fold axis is impossible in a periodic crystal.",
		},
		{
			at = "crystal_museum", title = "Real crystals",
			text = "Salt, copper, iron, diamond: the same rules, in real materials. Punch a gold clue crystal to test yourself.",
		},
	},
	regions = {
		{
			id = "mirror_plaza",
			showcase = {
				text = "Half a butterfly was built west of the mirror; the mirror made the other wing.",
				-- The body bulges out on one side. A perfectly flat butterfly would lie in a second mirror
				-- plane (its own), and the build would be mm2 rather than m.
				blocks = { { 12, 7, 13, "black" }, { 12, 6, 13, "black" }, { 12, 5, 13, "black" } },
				art = {
					{
						plane = "xy", at = { 6, 0, 12 },
						key = { O = "orange", Y = "yellow", K = "black" },
						rows = {
							"....K..",
							".....K.",
							"OOO...K",
							"OYYOO.K",
							"OYYOOOK",
							".OOOOOK",
							"...OOOK",
							"..OOOOK",
							".OYOOOK",
							"..OO..K",
						},
					},
				},
			},
			style = "plaza",
			name = "Mirror Plaza",
			tier = 1,
			symbol = "m",
			generators = { "-x,y,z" },
			anchor = "floor",
			at = { 388, 1, 388 },
			size = { 25, 16, 25 },
			explain = {
				[1] = {
					"A mirror plane (m) runs through the middle of this plaza, north to south.",
					"Everything you build is reflected to the other side.",
					"Task: build half a butterfly or a letter, and watch the mirror finish it.",
					"Notice: build a shape that points left, and its image points right. A mirror swaps handedness.",
				},
				[3] = {
					"A mirror is the same as a 2-fold rotation followed by an inversion, so it is also written -2.",
					"Like inversion, a mirror is an 'improper' operation: no way of moving a solid object through space can produce it.",
				},
			},
			quiz = {
				[1] = {
					{
						q = "You place one block next to the mirror plane, not on it. How many blocks appear in total, counting yours?",
						options = { "1", "2", "4" },
						answer = 1,
						why = "The group m has 2 operations: do nothing, and reflect. So a block off the plane gives 2.",
					},
					{
						q = "You place a block exactly on the mirror plane. How many blocks appear?",
						options = { "1", "2" },
						answer = 0,
						why = "A block on the plane is its own mirror image.",
					},
				},
				[3] = {
					{
						q = "A mirror plane is the same as which rotoinversion?",
						options = { "-1", "-2", "-4" },
						answer = 1,
						why = "Rotating 180 degrees and then inverting through a point on the axis gives a reflection in the plane perpendicular to that axis: m = -2.",
					},
				},
			},
		},
		{
			id = "twofold_yard",
			showcase = {
				text = "One propeller blade was built; the 2-fold axis added the second, half a turn round.",
				blocks = {
					{ 12, 0, 12, "grey" }, { 12, 1, 12, "grey" }, { 12, 2, 12, "grey" }, { 12, 3, 12, "grey" },
					{ 13, 3, 12, "blue" }, { 14, 3, 12, "blue" }, { 15, 3, 12, "blue" }, { 16, 3, 12, "blue" },
					{ 17, 3, 12, "blue" }, { 17, 3, 13, "blue" }, { 17, 3, 14, "blue" },
				},
			},
			style = "yard",
			name = "Twofold Yard",
			tier = 1,
			symbol = "2",
			generators = { "-x,-y,z" },
			anchor = "floor",
			at = { 548, 1, 388 },
			size = { 25, 16, 25 },
			explain = {
				[1] = {
					"A 2-fold rotation axis stands upright in the middle of this yard.",
					"Each block is copied half a turn (180 degrees) around it.",
					"Task: build one blade of a propeller and watch the second appear.",
					"Notice: a rotation never turns a left hand into a right hand.",
				},
			},
			quiz = {
				[1] = {
					{
						q = "How many times must you apply a half turn to get back to where you started?",
						options = { "1", "2", "4" },
						answer = 1,
						why = "Two half turns make one full turn. That is why it is called 2-fold.",
					},
				},
			},
		},
		{
			id = "fourfold_tower",
			showcase = {
				text = "One windmill sail was built; the 4-fold axis added the other three.",
				blocks = {
					{ 12, 0, 12, "brown" }, { 12, 1, 12, "brown" }, { 12, 2, 12, "brown" }, { 12, 3, 12, "brown" },
					{ 12, 4, 12, "brown" }, { 12, 5, 12, "brown" }, { 12, 6, 12, "brown" }, { 12, 7, 12, "brown" },
					{ 13, 7, 12, "white" }, { 14, 7, 12, "white" }, { 15, 7, 12, "white" }, { 16, 7, 12, "white" },
					{ 17, 7, 12, "white" }, { 14, 7, 13, "red" }, { 15, 7, 13, "red" }, { 16, 7, 13, "red" }, { 17, 7, 13, "red" },
				},
			},
			style = "tower",
			name = "Fourfold Tower",
			tier = 1,
			symbol = "4",
			generators = { "-y,x,z" },
			anchor = "floor",
			at = { 708, 1, 388 },
			size = { 25, 16, 25 },
			explain = {
				[1] = {
					"A 4-fold rotation axis stands upright in the middle of this tower.",
					"Each block is copied a quarter turn (90 degrees) at a time around it.",
					"Task: build a windmill with four blades by building just one.",
					"An n-fold axis turns by 360/n degrees; doing it n times brings you back to the start.",
				},
			},
			quiz = {
				[1] = {
					{
						q = "You place one block away from the axis. How many blocks appear in total, counting yours?",
						options = { "2", "4", "8" },
						answer = 1,
						why = "The group 4 has 4 operations: turns of 0, 90, 180 and 270 degrees.",
					},
					{
						q = "Which rotation is hidden inside a 4-fold axis?",
						options = { "2-fold", "3-fold", "6-fold" },
						answer = 0,
						why = "Two quarter turns make a half turn, so every 4-fold axis is also a 2-fold axis.",
					},
				},
			},
		},
		{
			id = "inversion_core",
			showcase = {
				text = "A blue corner with three arms was built near the bottom; inversion put an upside-down copy at the opposite corner.",
				blocks = {
					-- Three arms of different lengths (4, 3, 2), so the shape has no symmetry of its own.
					{ 4, 4, 4, "blue" }, { 5, 4, 4, "blue" }, { 6, 4, 4, "blue" }, { 7, 4, 4, "blue" },
					{ 4, 5, 4, "blue" }, { 4, 6, 4, "blue" }, { 4, 4, 5, "blue" },
				},
			},
			style = "cube",
			name = "Inversion Core",
			tier = 1,
			symbol = "-1",
			generators = { "-x,-y,-z" },
			anchor = "centre",
			at = { 870, 3, 390 },
			size = { 21, 21, 21 },
			explain = {
				[1] = {
					"An inversion centre (-1, say 'bar one') floats in the middle of this cube.",
					"Each block is sent straight through the centre to the same distance on the other side.",
					"Fly in (press K to fly). Right-click with a block while pointing at nothing to place it 3 blocks in front of you.",
					"Build near a corner: the copy appears at the opposite corner, upside down.",
					"In coordinates: (x, y, z) becomes (-x, -y, -z).",
				},
			},
			quiz = {
				[1] = {
					{
						q = "A block sits 3 blocks above and 2 blocks east of the centre. Where is its copy?",
						options = { "3 above, 2 west", "3 below, 2 west", "3 below, 2 east" },
						answer = 1,
						why = "Inversion reverses every direction: above becomes below and east becomes west.",
					},
					{
						q = "Does inversion turn a left hand into a right hand?",
						options = { "Yes", "No" },
						answer = 0,
						why = "Yes. Like a mirror, inversion is an improper operation and reverses handedness.",
					},
				},
			},
		},
		{
			id = "translation_hall",
			showcase = {
				text = "One cell got a red block at its corner and a blue one at its centre; the lattice repeated them. Caesium chloride is built this way: one kind of ion at the cell corners, the other at the cell centre.",
				blocks = { { 0, 0, 0, "red" }, { 4, 4, 4, "blue" } },
			},
			style = "hall",
			name = "Translation Hall",
			tier = 1,
			symbol = "P1",
			generators = {  },
			periodic = { cell = { 8, 8, 8 }, counts = { 3, 3, 3 } },
			at = { 1028, 2, 388 },
			explain = {
				[1] = {
					"This hall is a crystal: 27 identical boxes (unit cells) stacked 3 by 3 by 3.",
					"Build anything in one box and it is copied into every box.",
					"A crystal is a motif (your build) repeated on a lattice (the grid of boxes).",
					"The moves from one box to the next are translations.",
				},
				[4] = {
					"The box is the unit cell; its edge lengths are the lattice parameters (here 8 blocks each way).",
					"A real crystal repeats its unit cell billions of times in every direction.",
					"Only lattice translations are imposed here, so the space group is P1.",
				},
			},
			quiz = {
				[1] = {
					{
						q = "You place one block. How many blocks appear in the hall?",
						options = { "1", "6", "27" },
						answer = 2,
						why = "One copy in each of the 3 x 3 x 3 = 27 unit cells.",
					},
				},
			},
		},
		{
			id = "twin_mirrors",
			showcase = {
				text = "One green seat was built; two mirrors made four.",
				blocks = {
					{ 15, 0, 15, "green" }, { 15, 1, 15, "green" }, { 15, 2, 15, "green" }, { 16, 2, 15, "green" },
					{ 17, 2, 15, "green" }, { 17, 2, 16, "green" },
				},
			},
			style = "plaza",
			name = "Twin Mirrors",
			tier = 2,
			symbol = "mm2",
			generators = { "x,-y,z", "-x,y,z" },
			anchor = "floor",
			at = { 388, 1, 548 },
			size = { 25, 16, 25 },
			explain = {
				[2] = {
					"Two mirror planes meet at right angles along the vertical line in the middle.",
					"Build one block and look closely: there are four blocks, but only two mirrors.",
					"Two mirrors at an angle make a rotation by twice that angle. 2 x 90 = 180 degrees, so a 2-fold axis appears where they meet.",
					"The name mm2 lists the two mirrors and the 2-fold axis they create.",
				},
			},
			quiz = {
				[2] = {
					{
						q = "How many copies does one block off the mirrors make, counting yours?",
						options = { "2", "3", "4" },
						answer = 2,
						why = "mm2 has 4 operations: nothing, mirror 1, mirror 2, and the 2-fold rotation.",
					},
					{
						q = "Two mirror planes meet at 45 degrees. What rotation do they create?",
						options = { "2-fold (180 deg)", "4-fold (90 deg)", "8-fold (45 deg)" },
						answer = 1,
						why = "Twice the angle: 2 x 45 = 90 degrees, a 4-fold rotation.",
					},
				},
			},
		},
		{
			id = "monoclinic_cube",
			showcase = {
				text = "One purple hook was built; the axis, the mirror and the inversion centre they make gave four.",
				blocks = { { 12, 12, 13, "purple" }, { 13, 12, 13, "purple" }, { 13, 13, 13, "purple" }, { 13, 13, 14, "purple" } },
			},
			style = "cube",
			name = "Monoclinic Cube",
			tier = 2,
			symbol = "2/m",
			generators = { "-x,-y,z", "x,y,-z" },
			anchor = "centre",
			at = { 550, 3, 550 },
			size = { 21, 21, 21 },
			explain = {
				[2] = {
					"A vertical 2-fold axis, plus a horizontal mirror plane perpendicular to it.",
					"'/' in the name means 'with a mirror perpendicular to', so 2/m reads 'two over m'.",
					"Combine the two and a third operation appears for free: an inversion centre where axis and mirror meet.",
					"Task: build near a top corner and find the copy at the opposite bottom corner.",
				},
			},
			quiz = {
				[2] = {
					{
						q = "Which extra operation do a 2-fold axis and a perpendicular mirror create together?",
						options = { "A 4-fold axis", "An inversion centre", "A second mirror" },
						answer = 1,
						why = "Half turn about z: (x,y,z) -> (-x,-y,z). Then mirror: z -> -z. Together: (-x,-y,-z), an inversion.",
					},
					{
						q = "How many operations does 2/m have?",
						options = { "2", "3", "4" },
						answer = 2,
						why = "Identity, the 2-fold rotation, the mirror, and the inversion.",
					},
				},
			},
		},
		{
			id = "square_court",
			showcase = {
				text = "One petal was laid on the floor; four mirrors and the 4-fold axis made a flower of eight.",
				blocks = {
					{ 12, 0, 12, "yellow" }, { 12, 1, 12, "yellow" }, { 13, 0, 12, "pink" }, { 14, 0, 12, "pink" },
					{ 15, 0, 13, "pink" }, { 16, 0, 14, "magenta" },
				},
			},
			style = "plaza",
			name = "Square Court",
			tier = 2,
			symbol = "4mm",
			generators = { "-y,x,z", "x,-y,z" },
			anchor = "floor",
			at = { 708, 1, 548 },
			size = { 25, 16, 25 },
			explain = {
				[2] = {
					"A 4-fold axis with mirror planes: two along the sides and two along the diagonals.",
					"The region was given one 4-fold axis and one mirror; combining them produces four mirrors.",
					"This is the symmetry of a square seen from above.",
				},
			},
			quiz = {
				[2] = {
					{
						q = "How many copies does one block in a general position make, counting yours?",
						options = { "4", "8", "16" },
						answer = 1,
						why = "4mm has 8 operations: 4 rotations and 4 mirrors.",
					},
					{
						q = "How many mirror planes does 4mm have?",
						options = { "1", "2", "4" },
						answer = 2,
						why = "Turning the side mirror by 90 degrees gives a second side mirror, and combining a mirror with a quarter turn gives the two diagonal mirrors: 2 + 2 = 4.",
					},
				},
			},
		},
		{
			id = "orthorhombic_cube",
			showcase = {
				text = "One orange hook was built; three mirrors made eight.",
				blocks = { { 12, 11, 13, "orange" }, { 13, 11, 13, "orange" }, { 13, 12, 13, "orange" } },
			},
			style = "cube",
			name = "Orthorhombic Cube",
			tier = 2,
			symbol = "mmm",
			generators = { "-x,y,z", "x,-y,z", "x,y,-z" },
			anchor = "centre",
			at = { 870, 3, 550 },
			size = { 21, 21, 21 },
			explain = {
				[2] = {
					"Three mirror planes, all at right angles, each through the middle of a shoebox and parallel to one pair of its faces.",
					"Each pair of mirrors makes a 2-fold axis, and all three together make an inversion centre.",
					"The full name is 2/m 2/m 2/m; mmm is the short form.",
				},
			},
			quiz = {
				[2] = {
					{
						q = "How many operations does mmm have?",
						options = { "3", "6", "8" },
						answer = 2,
						why = "Identity, 3 mirrors, 3 two-fold rotations and the inversion: 8.",
					},
				},
			},
		},
		{
			id = "diagonal_cube",
			showcase = {
				text = "A cyan hook was built off the diagonal and made three; the white block sits on the 3-fold axis and stays single.",
				blocks = { { 12, 10, 10, "cyan" }, { 13, 10, 10, "cyan" }, { 13, 11, 10, "cyan" }, { 13, 13, 13, "white" } },
			},
			style = "cube",
			name = "Diagonal Cube",
			tier = 3,
			symbol = "3",
			generators = { "z,x,y" },
			anchor = "centre",
			at = { 1030, 3, 550 },
			size = { 21, 21, 21 },
			explain = {
				[3] = {
					"A 3-fold axis runs along the long diagonal of this cube, from one corner to the opposite corner.",
					"It turns the cube by 120 degrees: east goes to north, north goes to up, and up goes to east.",
					"In coordinates it just cycles them: (x, y, z) -> (z, x, y).",
					"A cube has four such diagonals, which is what makes cubic crystals special.",
				},
			},
			quiz = {
				[3] = {
					{
						q = "How many copies does one block off the diagonal make, counting yours?",
						options = { "3", "4", "6" },
						answer = 0,
						why = "Turns of 0, 120 and 240 degrees.",
					},
				},
			},
		},
		{
			id = "rotoinversion_room",
			showcase = {
				text = "One magenta hook was built; -4 made four, alternately up and down.",
				blocks = { { 12, 13, 11, "magenta" }, { 13, 13, 11, "magenta" }, { 13, 14, 11, "magenta" } },
			},
			style = "room",
			name = "Rotoinversion Room",
			tier = 3,
			symbol = "-4",
			generators = { "y,-x,-z" },
			anchor = "centre",
			at = { 390, 3, 710 },
			size = { 21, 21, 21 },
			explain = {
				[3] = {
					"-4 (say 'bar four'): turn a quarter turn about the vertical axis, then invert through the centre.",
					"Neither step alone is a symmetry here; only the combination is.",
					"Doing it twice gives a plain half turn, so -4 contains a 2-fold axis but no 4-fold axis and no inversion centre.",
				},
			},
			quiz = {
				[3] = {
					{
						q = "Which of these does the group -4 contain?",
						options = { "A 4-fold axis", "An inversion centre", "A 2-fold axis" },
						answer = 2,
						why = "(-4)^2 = a half turn. The 4-fold rotation and the inversion only occur together, never separately.",
					},
				},
			},
		},
		{
			id = "bar_three_room",
			showcase = {
				text = "One green hook was built; -3 made six around the diagonal.",
				blocks = { { 12, 13, 11, "lime" }, { 13, 13, 11, "lime" }, { 13, 14, 11, "lime" } },
			},
			style = "room",
			name = "Bar-Three Room",
			tier = 3,
			symbol = "-3",
			generators = { "-z,-x,-y" },
			anchor = "centre",
			at = { 550, 3, 710 },
			size = { 21, 21, 21 },
			explain = {
				[3] = {
					"-3 (say 'bar three'): turn a third of a turn about the long diagonal of the cube, then invert through the centre.",
					"Doing it twice gives a plain 3-fold rotation, and doing it three times gives the inversion itself.",
					"So -3 contains both a 3-fold axis and an inversion centre. Compare the Rotoinversion Room: -4 contains neither a 4-fold axis nor an inversion centre.",
					"Calcite, the mineral of limestone and marble, has a -3 axis: its point group is -3m.",
				},
			},
			quiz = {
				[3] = {
					{
						q = "Which of these does the group -3 contain?",
						options = { "A 3-fold axis and an inversion centre", "A 3-fold axis only", "An inversion centre only" },
						answer = 0,
						why = "(-3) twice is a 3-fold rotation and (-3) three times is the inversion, so both are in the group. It has 6 operations.",
					},
					{
						q = "You place one block off the diagonal and away from the centre. How many blocks appear in total?",
						options = { "3", "6", "12" },
						answer = 1,
						why = "-3 has 6 operations: the identity, two 3-fold rotations, the inversion and two -3 rotoinversions.",
					},
				},
			},
		},
		{
			id = "kaleidoscope",
			showcase = {
				text = "Three blocks were placed: yellow off every element (48 copies), green on a 3-fold axis (8, the corners of a cube) and red on a 4-fold axis (6, the corners of an octahedron).",
				blocks = { { 12, 13, 15, "yellow" }, { 14, 14, 14, "green" }, { 10, 10, 16, "red" } },
			},
			style = "cube",
			name = "Kaleidoscope",
			tier = 3,
			symbol = "m-3m",
			generators = { "z,x,y", "-y,x,z", "-x,-y,-z" },
			anchor = "centre",
			at = { 710, 3, 710 },
			size = { 21, 21, 21 },
			explain = {
				[3] = {
					"The full symmetry of a cube: m-3m, the highest point symmetry a crystal can have.",
					"3 four-fold axes, 4 three-fold axes, 6 two-fold axes, 9 mirrors and an inversion centre.",
					"Place one block anywhere off the symmetry elements and it becomes 48.",
					"Metals such as copper, iron and aluminium have this symmetry.",
				},
			},
			quiz = {
				[3] = {
					{
						q = "How many operations does m-3m have?",
						options = { "24", "32", "48" },
						answer = 2,
						why = "48: the 24 rotations of a cube, and each of those combined with inversion.",
					},
				},
			},
		},
		{
			id = "impossible_room",
			style = "room",
			name = "Impossible Room",
			tier = 3,
			symbol = "1",
			generators = {  },
			anchor = "floor",
			at = { 868, 1, 708 },
			size = { 25, 16, 25 },
			explain = {
				[3] = {
					"This room was meant to have a 6-fold axis. It cannot be built on a block grid.",
					"Turn a square grid by 60 degrees and the grid points no longer land on grid points.",
					"Every operation that maps the block grid onto itself just permutes x, y and z and flips signs; none of these is a 6-fold rotation.",
					"So only 25 of the 32 crystal point groups fit here. The 7 hexagonal ones need a hexagonal lattice, like graphite or snowflakes.",
					"No lattice at all allows a 5-fold axis: that is the crystallographic restriction.",
				},
			},
			quiz = {
				[3] = {
					{
						q = "Which rotation axes can a periodic crystal have?",
						options = { "1, 2, 3, 4 and 6", "Any n", "1, 2, 3, 4, 5 and 6" },
						answer = 0,
						why = "Rotations must map lattice points to lattice points. That only allows 1-, 2-, 3-, 4- and 6-fold axes.",
					},
				},
			},
		},
		{
			id = "screw_hall",
			showcase = {
				text = "One orange step was built; the 2_1 screw axis turned it and lifted it, making a spiral staircase.",
				blocks = { { 1, 0, 1, "orange" }, { 2, 0, 1, "orange" } },
			},
			style = "hall",
			name = "Screw Hall",
			tier = 4,
			symbol = "P2_1",
			generators = { "-x,-y,z+1/2" },
			periodic = { cell = { 6, 6, 6 }, counts = { 3, 3, 3 } },
			at = { 1031, 2, 711 },
			explain = {
				[4] = {
					"A 2_1 screw axis: turn half a turn about a vertical axis, then rise by half a unit cell.",
					"Build a block and follow its copies upward: they spiral like a staircase.",
					"A screw axis needs a repeating translation, so it occurs in periodic structures such as crystals, never in the symmetry of a single finite object.",
				},
			},
			quiz = {
				[4] = {
					{
						q = "Apply the 2_1 screw operation twice. What do you get?",
						options = { "Nothing changes", "A shift of one whole cell upward", "A half turn" },
						answer = 1,
						why = "Two half turns make a full turn, and two half-cell rises make one full cell: a lattice translation.",
					},
					{
						q = "Can a single, finite object, like a vase, have a 2_1 screw axis?",
						options = { "Yes", "No" },
						answer = 1,
						why = "No. A screw includes a shift, and a finite object cannot be shifted onto itself. Screw axes need a repeating structure.",
					},
				},
			},
		},
		{
			id = "glide_hall",
			showcase = {
				text = "One footprint was built; the glide plane made a trail of left and right prints.",
				blocks = { { 1, 1, 1, "light_blue" }, { 1, 1, 2, "light_blue" }, { 2, 1, 1, "light_blue" } },
			},
			style = "hall",
			name = "Glide Hall",
			tier = 4,
			symbol = "Pa",
			generators = { "x+1/2,-y,z" },
			periodic = { cell = { 6, 6, 6 }, counts = { 4, 1, 4 } },
			at = { 388, 2, 868 },
			explain = {
				[4] = {
					"A glide plane: reflect in a vertical plane, then slide half a cell along it.",
					"Like footprints in snow: left, right, left, right, each one a mirror image moved forward.",
				},
			},
			quiz = {
				[4] = {
					{
						q = "A glide reflection is a reflection combined with what?",
						options = { "A rotation", "A translation parallel to the plane", "An inversion" },
						answer = 1,
						why = "The slide is half a lattice translation, parallel to the mirror plane.",
					},
					{
						q = "Apply the glide twice. What do you get?",
						options = { "Nothing changes", "A shift of one whole cell along the plane", "A plain reflection" },
						answer = 1,
						why = "Two reflections cancel, and two half-cell slides make a whole cell: a lattice translation.",
					},
				},
			},
		},
		{
			id = "spiral_tower",
			style = "tower",
			name = "Spiral Tower",
			tier = 4,
			symbol = "P4_1",
			generators = { "-y,x,z+1/4" },
			periodic = { cell = { 8, 8, 8 }, counts = { 2, 3, 2 } },
			at = { 552, 2, 872 },
			showcase = {
				text = "One step was built; the 4_1 screw axis turned and lifted it into a spiral staircase, one quarter turn and two blocks up at a time.",
				blocks = { { 1, 0, 1, "red" }, { 2, 0, 1, "red" }, { 3, 0, 1, "red" } },
			},
			explain = {
				[4] = {
					"A 4_1 screw axis: a quarter turn about the vertical axis, then a rise of a quarter of a cell (here 2 blocks).",
					"Four steps make one full turn and one full cell, so the copies climb like a spiral staircase.",
					"Its mirror image turns the other way, and is called 4_3. Screw axes can give crystals a handedness:",
					"quartz has 3-fold screw axes (3_1 or 3_2), which is why there are left- and right-handed quartz crystals.",
					"Try /step here to see each turn-and-rise named, or /byhand to place the steps yourself.",
				},
			},
			quiz = {
				[4] = {
					{
						q = "How many 4_1 steps bring a block back directly above where it started, exactly one cell higher?",
						options = { "2", "4", "8" },
						answer = 1,
						why = "Four quarter turns make one full turn, and four quarter-cell rises make one whole cell.",
					},
					{
						q = "What is the mirror image of a 4_1 screw axis?",
						options = { "A 4_3 screw axis, turning the other way", "A 4_1 screw axis again", "A plain 4-fold rotation axis" },
						answer = 0,
						why = "A mirror reverses the sense of the turn but not the rise, so the right-handed 4_1 staircase becomes the left-handed 4_3.",
					},
				},
			},
		},
		{
			id = "mystery_lab",
			style = "cube",
			name = "Mystery Lab",
			tier = 4,
			symbol = "?",
			hidden = "4/m",
			generators = { "-y,x,z", "x,y,-z" },
			anchor = "centre",
			at = { 710, 3, 870 },
			size = { 21, 21, 21 },
			explain = {
				[4] = {
					"This lab has a hidden symmetry. Build, look at the copies, and work out the point group.",
					"Tip: build near the centre first, then far from it. Look for axes, mirrors and an inversion centre.",
				},
			},
			quiz = {
				[4] = {
					{
						q = "What is the point group of the Mystery Lab?",
						options = { "4mm", "4/m", "-4", "422" },
						answer = 1,
						why = "A vertical 4-fold axis with a horizontal mirror perpendicular to it: 4/m. It also has an inversion centre.",
					},
					{
						q = "A build has symmetry mmm. Which operations does it have that a 2/m build lacks?",
						options = { "Two more mirrors and two more 2-fold axes", "An inversion centre", "A 4-fold axis" },
						answer = 0,
						why = "2/m has one 2-fold axis, one mirror and an inversion centre. mmm has three of each kind of axis and mirror, plus the inversion centre.",
					},
				},
			},
		},
		{
			id = "free_lab",
			style = "cube",
			name = "Free Lab",
			tier = 4,
			symbol = "1",
			generators = {  },
			anchor = "centre",
			free = true,
			at = { 870, 3, 870 },
			size = { 21, 21, 21 },
			explain = {
				[4] = {
					"Your lab. Build anything, then type /whatsymmetry to have the exact point group worked out.",
					"Type /symmetry followed by a description (for example: a fourfold axis with mirrors) to give the lab that symmetry.",
					"Try asking for a sixfold axis and see what happens.",
					"Challenges: type /challenge to get a target symmetry, build it, then check it with /whatsymmetry.",
				},
			},
			challenges = {
				{
					target = "2/m",
					text = "Build something whose symmetry is exactly 2/m, not mmm.",
				},
				{
					target = "4mm",
					text = "Build something with exactly 4mm symmetry: a 4-fold axis and mirrors, but nothing upside down.",
				},
				{
					target = "-4",
					text = "Hard: build something with a -4 axis but no 4-fold axis.",
				},
				{
					target = "m-3m",
					text = "Build something with the full symmetry of a cube.",
				},
			},
		},
		{
			id = "mirror_tiles",
			showcase = {
				text = "One red hook per cell was placed; the mirror lines tiled the floor.",
				blocks = { { 1, 0, 1, "red" }, { 2, 0, 1, "red" }, { 1, 0, 2, "red" } },
			},
			style = "garden",
			name = "Mirror Tiles",
			tier = 4,
			symbol = "pmm",
			generators = { "-x,y,z", "x,-y,z" },
			periodic = { cell = { 6, 1, 6 }, counts = { 6, 1, 6 } },
			at = { 1022, 1, 862 },
			explain = {
				[4] = {
					"A floor pattern with plane group pmm: mirror lines in two directions at right angles, repeated in every cell.",
					"Place blocks on the floor and the pattern tiles the whole garden. Where two mirror lines cross, there is a 2-fold rotation point.",
					"A plane group is the symmetry of a repeating flat pattern. There are exactly 17; this garden shows four.",
				},
			},
			quiz = {
				[4] = {
					{
						q = "One block in a general position: how many copies appear in each unit cell, counting yours?",
						options = { "2", "4", "8" },
						answer = 1,
						why = "pmm has 4 operations per cell: the identity, two mirrors and the 2-fold rotation where they cross.",
					},
					{
						q = "Of the 17 plane groups, how many can be built on a square block grid?",
						options = { "12", "17", "5" },
						answer = 0,
						why = "12. The other 5 need 3-fold or 6-fold rotations, and turning a square grid by 120 or 60 degrees moves grid points off the grid.",
					},
				},
			},
		},
		{
			id = "glide_tiles",
			showcase = {
				text = "One cyan arrow was placed; turns and glides tiled the floor.",
				blocks = { { 0, 0, 1, "cyan" }, { 1, 0, 1, "cyan" }, { 2, 0, 1, "cyan" }, { 1, 0, 2, "cyan" } },
			},
			style = "garden",
			name = "Glide Tiles",
			tier = 4,
			symbol = "pgg",
			generators = { "-x,-y,z", "-x+1/2,y+1/2,z" },
			periodic = { cell = { 6, 1, 6 }, counts = { 6, 1, 6 } },
			at = { 382, 1, 1022 },
			explain = {
				[4] = {
					"Plane group pgg: glide lines in two directions and 2-fold rotation points, but no mirror lines at all.",
					"Each copy is either turned half a turn, or reflected and slid half a cell along the glide line.",
					"Build an arrow on the floor and follow its copies: they alternate like footprints.",
				},
			},
			quiz = {
				[4] = {
					{
						q = "Does pgg have any mirror lines?",
						options = { "Yes, two", "No, only glide lines", "Yes, four" },
						answer = 1,
						why = "Every reflection in pgg comes with a slide of half a cell, so each one is a glide, never a plain mirror.",
					},
				},
			},
		},
		{
			id = "pinwheel_tiles",
			showcase = {
				text = "One purple hook was placed; the 4-fold points turned it into pinwheels.",
				blocks = { { 1, 0, 0, "purple" }, { 2, 0, 0, "purple" }, { 2, 0, 1, "purple" } },
			},
			style = "garden",
			name = "Pinwheel Tiles",
			tier = 4,
			symbol = "p4",
			generators = { "-y,x,z" },
			periodic = { cell = { 6, 1, 6 }, counts = { 6, 1, 6 } },
			at = { 542, 1, 1022 },
			explain = {
				[4] = {
					"Plane group p4: 4-fold rotation points, repeated in every cell, and no mirrors or glides.",
					"Without mirrors the pattern has a handedness: it turns one way, like a pinwheel, and its mirror image turns the other way.",
				},
			},
			quiz = {
				[4] = {
					{
						q = "One block in a general position: how many copies appear in each unit cell, counting yours?",
						options = { "2", "4", "8" },
						answer = 1,
						why = "p4 has 4 operations per cell: turns of 0, 90, 180 and 270 degrees.",
					},
				},
			},
		},
		{
			id = "weave_tiles",
			showcase = {
				text = "The same hook as next door was placed; the extra mirrors and glides of p4g weave it into a different pattern.",
				blocks = { { 1, 0, 0, "orange" }, { 2, 0, 0, "orange" }, { 2, 0, 1, "orange" } },
			},
			style = "garden",
			name = "Weave Tiles",
			tier = 4,
			symbol = "p4g",
			generators = { "-y,x,z", "-x+1/2,y+1/2,z" },
			periodic = { cell = { 6, 1, 6 }, counts = { 6, 1, 6 } },
			at = { 702, 1, 1022 },
			explain = {
				[4] = {
					"Plane group p4g: 4-fold rotation points with mirror lines and glide lines, but no mirror passes through a 4-fold point.",
					"Compare it with Pinwheel Tiles next door: the extra glides and mirrors double the number of copies.",
				},
			},
			quiz = {
				[4] = {
					{
						q = "One block in a general position: how many copies appear in each unit cell, counting yours?",
						options = { "4", "8", "16" },
						answer = 1,
						why = "p4g has 8 operations per cell: the 4 rotations of p4, each combined with a reflection or glide.",
					},
				},
			},
		},
	},
}
