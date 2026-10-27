"""Generate tileable textures for Esmiringhoy (all procedural, original).

Output: <out>/assets/textures/*.png
Usage: python3 gen_textures.py <out_dir>
"""
import sys
import os
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

OUT = os.path.join(sys.argv[1], "assets", "textures")
os.makedirs(OUT, exist_ok=True)
N = 1024
rng = np.random.default_rng(1337)


def spectral_noise(shape, scale, aniso=(1.0, 1.0), seed=None):
    """Tileable noise: white noise filtered in frequency space (periodic by construction)."""
    r = np.random.default_rng(seed)
    h, w = shape
    white = r.standard_normal(shape)
    fy = np.fft.fftfreq(h)[:, None] * aniso[0]
    fx = np.fft.fftfreq(w)[None, :] * aniso[1]
    f = np.sqrt(fx ** 2 + fy ** 2)
    sigma = scale / float(max(h, w))  # scale = rough feature count across the texture
    filt = np.exp(-(f ** 2) / (2 * sigma ** 2))
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * filt))
    out -= out.min()
    out /= out.max() + 1e-9
    return out


def fbm(shape, base_scale, octaves=5, aniso=(1.0, 1.0), seed=0, gain=0.5):
    total = np.zeros(shape)
    amp, norm = 1.0, 0.0
    s = base_scale
    for o in range(octaves):
        total += amp * spectral_noise(shape, s, aniso, seed + o * 17)
        norm += amp
        amp *= gain
        s *= 2.0
    return total / norm


def normal_from_height(h, strength=4.0):
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    nz = np.ones_like(h)
    n = np.stack([-dx, dy, nz], axis=-1)  # OpenGL-style (Godot default)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def to_rgb(arr):
    return (np.clip(arr, 0, 1) * 255).astype(np.uint8)


def colorize(t, c0, c1):
    c0 = np.array(c0) / 255.0
    c1 = np.array(c1) / 255.0
    return c0 + (c1 - c0) * t[..., None]


def save(name, arr, mode=None):
    Image.fromarray(arr, mode).save(os.path.join(OUT, name), optimize=True)
    print("wrote", name)


def voronoi(shape, n_points, seed):
    r = np.random.default_rng(seed)
    pts = r.random((n_points, 2))
    tree = cKDTree(pts, boxsize=1.0)
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w]
    q = np.stack([(yy + 0.5) / h, (xx + 0.5) / w], axis=-1).reshape(-1, 2)
    d, idx = tree.query(q, k=2)
    d1 = d[:, 0].reshape(shape)
    d2 = d[:, 1].reshape(shape)
    cell = idx[:, 0].reshape(shape)
    return d1, d2, cell


# ---------------------------------------------------------------- narra floor
def narra_floor():
    planks = 8  # planks across the texture (divides 1024 so it tiles)
    pw = N // planks
    grain = fbm((N, N), 3, 5, aniso=(14.0, 0.6), seed=10)  # long streaks along y
    fine = fbm((N, N), 40, 3, aniso=(10.0, 0.5), seed=20)
    xx = np.arange(N)[None, :].repeat(N, 0)
    plank_id = xx // pw
    tone = rng.uniform(-0.12, 0.12, planks)[plank_id]
    # end joints at random heights per plank
    yy = np.arange(N)[:, None].repeat(N, 1)
    offs = rng.integers(0, N, planks)[plank_id]
    joint = ((yy + offs) % (N // 2)) < 3
    seam = (xx % pw) < 3
    t = 0.35 + 0.45 * grain + 0.2 * fine + tone
    t = np.clip(t, 0, 1)
    col = colorize(t, (34, 22, 15), (92, 58, 38))
    col[seam | joint] *= 0.25
    wear = fbm((N, N), 6, 4, seed=30)
    col *= (0.8 + 0.35 * wear)[..., None]
    save("tex_wood_narra_floor_albedo.png", to_rgb(col))
    hgt = 0.6 * grain + 0.4 * fine
    hgt[seam | joint] = 0.0
    save("tex_wood_narra_floor_normal.png", normal_from_height(hgt, 6.0))
    rough = np.clip(0.55 + 0.35 * (1 - wear) + 0.1 * fine, 0, 1)
    save("tex_wood_narra_floor_rough.png", to_rgb(rough), "L")


# ------------------------------------------------------------- plaster wall
def plaster_wall():
    base = fbm((N, N), 4, 6, seed=40)
    blotch = fbm((N, N), 2, 3, seed=50)
    # vertical water stains: noise stretched down y
    drip = fbm((N, N), 3, 4, aniso=(6.0, 0.15), seed=60)
    drip = np.clip((drip - 0.5) * 4.0, 0, 1)
    d1, d2, _ = voronoi((N, N), 60, 70)
    crack = np.clip(1.0 - (d2 - d1) * 220.0, 0, 1)
    crack *= np.clip((fbm((N, N), 3, 3, seed=80) - 0.5) * 5, 0, 1)  # only some cell edges crack
    t = (base - 0.5) * 2.2 + (blotch - 0.5) * 1.6 + 0.55
    col = colorize(np.clip(t, 0, 1), (58, 52, 45), (156, 146, 128))
    col *= (1 - 0.45 * drip)[..., None]
    col *= (1 - 0.7 * crack)[..., None]
    save("tex_wall_plaster_albedo.png", to_rgb(col))
    hgt = 0.7 * base + 0.3 * blotch - 0.8 * crack
    save("tex_wall_plaster_normal.png", normal_from_height(hgt, 3.0))
    save("tex_wall_plaster_rough.png", to_rgb(np.clip(0.8 + 0.15 * base, 0, 1)), "L")


# --------------------------------------------------------- dark furniture wood
def dark_wood():
    grain = fbm((N, N), 4, 5, aniso=(12.0, 0.5), seed=90)
    rings = np.sin(grain * 40.0) * 0.5 + 0.5
    t = 0.5 * grain + 0.3 * rings
    col = colorize(np.clip(t, 0, 1), (18, 12, 9), (62, 40, 28))
    edge_wear = fbm((N, N), 8, 4, seed=100)
    col *= (0.85 + 0.3 * edge_wear)[..., None]
    save("tex_wood_dark_albedo.png", to_rgb(col))
    save("tex_wood_dark_normal.png", normal_from_height(0.6 * grain + 0.2 * rings, 4.0))
    save("tex_wood_dark_rough.png", to_rgb(np.clip(0.5 + 0.3 * edge_wear, 0, 1)), "L")


# ----------------------------------------------------------------- capiz shell
def capiz():
    n = 512
    cells = 4  # 4x4 panes per tile
    cw = n // cells
    yy, xx = np.mgrid[0:n, 0:n]
    frame = ((xx % cw) < 8) | ((yy % cw) < 8)
    pearl = fbm((n, n), 6, 5, seed=110)
    swirl = fbm((n, n), 3, 3, aniso=(1.0, 3.0), seed=120)
    t = 0.6 + 0.25 * pearl + 0.15 * swirl
    col = colorize(np.clip(t, 0, 1), (150, 160, 170), (232, 226, 210))
    # faint iridescence
    col[..., 0] += 0.04 * np.sin(swirl * 12)
    col[..., 2] += 0.05 * np.cos(pearl * 10)
    col[frame] = np.array([28, 20, 15]) / 255.0
    alpha = np.where(frame, 1.0, 0.55 + 0.25 * pearl)
    rgba = np.dstack([to_rgb(col), to_rgb(alpha)])
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "tex_capiz_shell.png"), optimize=True)
    print("wrote tex_capiz_shell.png")


# ------------------------------------------------------------------ kulambo net
def net():
    n = 512
    yy, xx = np.mgrid[0:n, 0:n]
    spacing = 8
    lines = ((xx % spacing) < 1) | ((yy % spacing) < 1)
    holes = fbm((n, n), 4, 3, seed=130) > 0.72
    alpha = np.where(lines & ~holes, 0.85, 0.0)
    dirt = fbm((n, n), 3, 3, seed=140)
    col = colorize(dirt, (150, 140, 118), (222, 212, 188))
    rgba = np.dstack([to_rgb(col), to_rgb(alpha)])
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "tex_fabric_net.png"), optimize=True)
    print("wrote tex_fabric_net.png")


# ------------------------------------------------------------- demon skin
def demon_skin():
    d1, d2, cell = voronoi((N, N), 140, 150)
    edge = d2 - d1
    crack = np.clip(1.0 - edge * 260.0, 0, 1) ** 1.5
    # break up cracks so not every cell edge glows
    gate = np.clip((fbm((N, N), 3, 3, seed=160) - 0.35) * 3.0, 0, 1)
    crack *= gate
    char = fbm((N, N), 8, 6, seed=170)
    plates = np.random.default_rng(5).uniform(-0.08, 0.08, cell.max() + 1)[cell]
    t = 0.25 + 0.45 * char + plates
    col = colorize(np.clip(t, 0, 1), (10, 7, 7), (52, 40, 36))
    col *= (1 - 0.9 * crack)[..., None]
    save("tex_demon_skin_albedo.png", to_rgb(col))
    hgt = char * 0.6 + np.clip(edge * 30, 0, 1) * 0.6 - crack * 0.8
    save("tex_demon_skin_normal.png", normal_from_height(hgt, 5.0))
    save("tex_demon_skin_rough.png", to_rgb(np.clip(0.75 + 0.2 * char, 0, 1)), "L")
    # emission mask: crack core + soft halo
    halo = np.clip(1.0 - edge * 90.0, 0, 1) * gate * 0.35
    mask = np.clip(crack + halo, 0, 1)
    save("tex_demon_cracks_mask.png", to_rgb(mask), "L")


# ------------------------------------------------------------------ decals
def decals():
    n = 256
    yy, xx = np.mgrid[0:n, 0:n]
    r = np.sqrt((xx - n / 2) ** 2 + (yy - n / 2) ** 2) / (n / 2)
    noise = fbm((n, n), 3, 4, seed=180)
    a = np.clip((1.0 - r) * 1.6 * (0.5 + noise), 0, 1)
    a[r > 1] = 0
    # claw scorch: 4 streaks
    streak = np.zeros((n, n))
    for i, x0 in enumerate([70, 105, 140, 175]):
        streak += np.clip(1 - np.abs(xx - (x0 + (yy - n / 2) * 0.08)) / 5.0, 0, 1) * ((yy > 20) & (yy < 236))
    scorch_a = np.clip(0.55 * a + streak * (0.6 + 0.4 * noise), 0, 1)
    col = colorize(noise, (8, 5, 4), (40, 18, 10))
    save("tex_decal_scorch.png", np.dstack([to_rgb(col), to_rgb(scorch_a)]), "RGBA")
    dust_a = np.clip((1 - r) * 0.9 * fbm((n, n), 5, 4, seed=190), 0, 1)
    dust_a[r > 1] = 0
    dcol = colorize(noise, (90, 82, 70), (140, 130, 112))
    save("tex_decal_dust.png", np.dstack([to_rgb(dcol), to_rgb(dust_a)]), "RGBA")


# --------------------------------------------------------- flashlight cookie
def cookie():
    n = 512
    yy, xx = np.mgrid[0:n, 0:n]
    r = np.sqrt((xx - n / 2) ** 2 + (yy - n / 2) ** 2) / (n / 2)
    hot = np.exp(-(r ** 2) / 0.08)
    body = np.clip(1.0 - r ** 2.2, 0, 1) * 0.75
    rings = 0.025 * np.sin(r * 38.0) * np.clip(1 - r, 0, 1)
    smudge = 0.08 * (fbm((n, n), 4, 3, seed=200) - 0.5)
    v = np.clip(hot * 0.4 + body + rings + smudge, 0, 1)
    v[r > 1] = 0
    save("tex_flashlight_cookie.png", to_rgb(v), "L")


if __name__ == "__main__":
    narra_floor()
    plaster_wall()
    dark_wood()
    capiz()
    net()
    demon_skin()
    decals()
    cookie()
