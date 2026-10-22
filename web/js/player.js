// First-person movement, as in the game: W A S D to walk, the mouse to look, Space to jump (or rise while flying), Shift to sink while flying, K to fly, J to go fast. The player is a box 0.6 wide and 1.75 tall that cannot pass through blocks.
//
// Positions are the game's (x east, y up, z north). yaw 0 faces north; a larger yaw turns left, as in Luanti.

const HALF = 0.3, HEIGHT = 1.75, EYE = 1.6;
const GRAVITY = 26, JUMP = 8.2;
const WALK = 4.4, FAST = 10, FLY = 8, FLY_FAST = 22;

export class Player {
  constructor() {
    this.pos = [0, 1, 0];       // feet, at the centre of the box's base
    this.vel = [0, 0, 0];
    this.yaw = 0;
    this.pitch = 0;
    this.flying = false;
    this.fast = false;
    this.onGround = false;
  }

  place(pos, yaw) {
    this.pos = [pos[0], pos[1] - 0.5, pos[2]];   // standing on the block below: a block at y = 0 has its top at 0.5
    this.vel = [0, 0, 0];
    this.yaw = yaw || 0;
    this.pitch = 0;
  }

  eye() { return [this.pos[0], this.pos[1] + EYE, this.pos[2]]; }

  // Unit vector the player looks along, in game coordinates.
  look() {
    const c = Math.cos(this.pitch);
    return [-Math.sin(this.yaw) * c, Math.sin(this.pitch), Math.cos(this.yaw) * c];
  }

  turn(dx, dy) {
    this.yaw -= dx * 0.0025;
    this.pitch = Math.max(-1.55, Math.min(1.55, this.pitch - dy * 0.0025));
  }

  // Whether the player's box at `p` would overlap a solid block.
  blocked(p, voxels) {
    const x0 = Math.round(p[0] - HALF + 0.001), x1 = Math.round(p[0] + HALF - 0.001);
    const y0 = Math.round(p[1] + 0.001), y1 = Math.round(p[1] + HEIGHT - 0.001);
    const z0 = Math.round(p[2] - HALF + 0.001), z1 = Math.round(p[2] + HALF - 0.001);
    for (let x = x0; x <= x1; x++)
      for (let y = y0; y <= y1; y++)
        for (let z = z0; z <= z1; z++) if (voxels.solid(x, y, z)) return true;
    return false;
  }

  // Whether a block at (x, y, z) would overlap the player, so it may not be placed there.
  occupies(x, y, z) {
    const p = this.pos;
    return x + 0.5 > p[0] - HALF && x - 0.5 < p[0] + HALF && y + 0.5 > p[1] && y - 0.5 < p[1] + HEIGHT
      && z + 0.5 > p[2] - HALF && z - 0.5 < p[2] + HALF;
  }

  update(dt, keys, voxels) {
    const f = (keys.KeyW ? 1 : 0) - (keys.KeyS ? 1 : 0);
    const s = (keys.KeyD ? 1 : 0) - (keys.KeyA ? 1 : 0);
    const speed = this.flying ? (this.fast ? FLY_FAST : FLY) : (this.fast ? FAST : WALK);
    // Forward along the ground (yaw only) and right, in game coordinates.
    const fx = -Math.sin(this.yaw), fz = Math.cos(this.yaw);
    const rx = Math.cos(this.yaw), rz = Math.sin(this.yaw);
    let mx = fx * f + rx * s, mz = fz * f + rz * s;
    const len = Math.hypot(mx, mz);
    if (len > 0) { mx = (mx / len) * speed; mz = (mz / len) * speed; }
    this.vel[0] = mx;
    this.vel[2] = mz;
    if (this.flying) {
      this.vel[1] = ((keys.Space ? 1 : 0) - (keys.ShiftLeft || keys.ShiftRight ? 1 : 0)) * speed;
    } else {
      this.vel[1] -= GRAVITY * dt;
      if (keys.Space && this.onGround) this.vel[1] = JUMP;
      this.vel[1] = Math.max(this.vel[1], -40);
    }
    // Move one axis at a time, so the player slides along walls instead of sticking to them.
    this.onGround = false;
    for (const a of [0, 2, 1]) {
      const d = this.vel[a] * dt;
      if (d === 0) continue;
      const p = this.pos.slice();
      p[a] += d;
      if (!this.blocked(p, voxels)) { this.pos = p; continue; }
      // A small step (half a block) is climbed when walking, as on the stairs of a plinth.
      if (a !== 1 && this.onGroundBefore && !this.flying) {
        const up = p.slice();
        up[1] = Math.round(this.pos[1]) + 0.5;
        if (up[1] - this.pos[1] <= 0.55 && !this.blocked(up, voxels)) { this.pos = up; continue; }
      }
      if (a === 1) {
        if (d < 0) {
          this.onGround = true;
          // Rest exactly on the block below.
          this.pos[1] = Math.round(this.pos[1]) - 0.5;
          if (this.blocked(this.pos, voxels)) this.pos[1] += 1;
        }
        this.vel[1] = 0;
      }
    }
    this.onGroundBefore = this.onGround || this.flying;
  }
}
