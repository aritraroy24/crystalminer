-- Shared immutable layout data for Gallery 2 furniture and hologram pedestals.

return {
	bounds = { x0 = -59, x1 = -17, z0 = -3, z1 = 59 },
	axis = -38,
	carpet = { x0 = -41, x1 = -35, z0 = -3, z1 = 59 },
	benches = {
		{ x0 = -53, x1 = -53, z0 = 7, z1 = 9, face = "w" },
		{ x0 = -23, x1 = -23, z0 = 7, z1 = 9, face = "e" },
		{ x0 = -53, x1 = -53, z0 = 39, z1 = 41, face = "w" },
		{ x0 = -23, x1 = -23, z0 = 39, z1 = 41, face = "e" },
	},
	pedestals = {
		columns = { -47, -29 }, rows = { 30, 40, 50 },
		centres = {
			{ x = -47, z = 30 }, { x = -29, z = 30 },
			{ x = -47, z = 40 }, { x = -29, z = 40 },
			{ x = -47, z = 50 }, { x = -29, z = 50 },
		},
	},
	haeuy = {
		centre = { x = -38, z = 20 }, radius = 4,
		base = { x0 = -39, x1 = -37, z0 = 19, z1 = 21 },
		plaque = { x = -38, z = 17.5 },
	},
	panel_z = { 4, 12, 28, 36, 44, 52 },
	door_x = { -41, -40 },
	wall_x = { -60, -16 },
}
