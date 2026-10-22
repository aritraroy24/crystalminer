#!/bin/sh
# Regenerates every generated file the crystal exhibits need (none of them is committed):
#   mods/crystalminer/exhibit_data.lua            the baked sample structures (the offline fallback)
#   mods/crystalminer/exhibit_colours.lua         element colours used by the baked samples
#   mods/crystalminer/textures/crystalminer_atom_*.png   one flat Jmol-colour texture per element
#   mods/crystalminer/models/crystalminer_atom.obj       the rounded atom mesh
#   tests/fixtures/exhibit_records.lua            parity fixtures for the unit tests
# Run it once after cloning, and again after changing data/mpcontribs/*.json or the tools.
# Inputs that are committed: data/mpcontribs/*.json and mods/crystalminer/exhibit_elements.lua.
set -e
cd "$(dirname "$0")/.."
python3 tools/make_exhibit_data.py
python3 tools/make_exhibit_colours.py
python3 tools/make_atoms.py
python3 tools/make_exhibit_fixtures.py
