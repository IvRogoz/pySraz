import sys
import pygame as pg
import moderngl
import numpy as np

# -----------------------------
# Settings
# -----------------------------
WINDOW_RES   = (1280, 720)
INTERNAL_RES = (320, 180)      # drop for speed: (256,144) or (200,112)
USE_NEAREST  = False           # True = pixelated + slightly faster
FPS_CAP      = 0               # 0 uncapped, 60 cap

# -----------------------------
# Pygame / GL init
# -----------------------------
pg.init()
pg.display.gl_set_attribute(pg.GL_CONTEXT_MAJOR_VERSION, 3)
pg.display.gl_set_attribute(pg.GL_CONTEXT_MINOR_VERSION, 3)
pg.display.gl_set_attribute(pg.GL_CONTEXT_PROFILE_MASK, pg.GL_CONTEXT_PROFILE_CORE)
pg.display.gl_set_attribute(pg.GL_DOUBLEBUFFER, 1)

try:
    pg.display.set_mode(WINDOW_RES, pg.OPENGL | pg.DOUBLEBUF | pg.RESIZABLE, vsync=0)
except TypeError:
    pg.display.set_mode(WINDOW_RES, pg.OPENGL | pg.DOUBLEBUF | pg.RESIZABLE)

pg.display.set_caption("Ulam cubes: black bg + muted darker reds + tails (low-res) + upscale")

# -----------------------------
# ModernGL context
# -----------------------------
try:
    ctx = moderngl.create_context(require=330)
except TypeError:
    ctx = moderngl.create_context()

# -----------------------------
# Fullscreen quad: pos.xy, uv.xy
# -----------------------------
quad = np.array([
    -1.0, -1.0,  0.0, 0.0,
     1.0, -1.0,  1.0, 0.0,
    -1.0,  1.0,  0.0, 1.0,
     1.0,  1.0,  1.0, 1.0,
], dtype="f4")
vbo = ctx.buffer(quad.tobytes())

# -----------------------------
# Common fullscreen vertex shader
# -----------------------------
FSQ_VERT = r"""
#version 330
in vec2 in_pos;
in vec2 in_uv;
out vec2 v_uv;
void main() {
    v_uv = in_uv;
    gl_Position = vec4(in_pos, 0.0, 1.0);
}
"""

# ============================================================
# PASS 1: Black background + muted darker red palette + temporal tail
# ============================================================
PASS1_FRAG = r"""
#version 330
uniform float iTime;
uniform vec3  iResolution;   // (w, h, 1)
in vec2 v_uv;
out vec4 fragColor;

#define PI 3.1415926535
#define clamps(x) clamp(x,0.,1.)

vec2 rotate2(float angle, vec2 position)
{
    mat2 m = mat2(cos(angle),-sin(angle),
                  sin(angle), cos(angle));
    return position*m;
}

float chess_dist(vec2 uv) { return max(abs(uv.x),abs(uv.y)); }

// smooth "less than"
float lthan(float a, float b) { return clamps(((b-a)*200.)+.5); }

float ulam_spiral(vec2 p)
{
    float x = abs(p.x);
    float y = abs(p.y);
    bool q  = x > y;

    x = q ? x : y;
    y = q ? p.x + p.y : p.x - p.y;
    y = abs(y) + 4.0 * x * x + 1.0;
    x *= 2.0;

    return q ? (p.x > 0.0 ? y - x - x : y)
             : (p.y > 0.0 ? y - x : y + x);
}

// Muted dark red palette (fixed family, only slight hue drift)
vec3 muted_red(float k)
{
    // k in [0..1]
    // deep maroon -> muted red -> dull orange-red (still dark)
    vec3 a = vec3(0.10, 0.02, 0.02);
    vec3 b = vec3(0.32, 0.06, 0.05);
    vec3 c = vec3(0.55, 0.12, 0.07);
    vec3 col = mix(a, b, smoothstep(0.0, 0.6, k));
    col = mix(col, c, smoothstep(0.6, 1.0, k));
    return col;
}

// one frame of the moving pattern, returns COLOR (not just mask)
vec3 drawing_color(vec2 uv, float time)
{
    time = fract(time * 0.6);

    // same motion logic as original
    uv = rotate2((-time*(PI/2.0))+(PI/2.0), uv);
    uv /= pow(3.0, fract(time));
    uv *= 5.0;

    float s = fract(time);
    vec3 col = vec3(0.0);

    // 3x3 squares
    for (float ii = 0.0; ii < 9.0; ii++) {
        vec2 base = vec2(mod(ii,3.0), floor(ii/3.0)) - 1.0;
        vec2 p = base;

        // move squares (original)
        p += p * pow(max((s*8.0) - (9.0 - ulam_spiral(-p)), 0.0), 2.0);

        float d = chess_dist(uv - p);

        // fill + soft edge (cube-ish)
        float fill = lthan(d, 0.5);
        float edge = smoothstep(0.55, 0.47, d);
        float glow = smoothstep(0.95, 0.55, d) * 0.25;

        // index-driven shade within the red family
        float sp = ulam_spiral(-base);
        float k = fract(sp * 0.11 + ii * 0.07 + iTime * 0.03);

        // keep it muted: compress range and darken
        k = 0.15 + 0.55 * k;

        vec3 sq = muted_red(k);

        // darker overall + only a little highlight
        vec3 sq_col = sq * (0.60 * fill + 0.85 * edge) + sq * glow;

        col += sq_col;
    }

    // global darkening to keep it muted
    col *= 0.85;

    return col;
}

void mainImage(out vec4 outColor, in vec2 fragCoord)
{
    vec2 uv = (fragCoord.xy / iResolution.xy) - 0.5;
    uv.x *= iResolution.x / iResolution.y;

    float time = iTime;

    // --------- TAIL (temporal accumulation) ----------
    // knobs
    const int SAMPLES = 18;
    float dt = 0.010;
    float decay = 0.82;

    vec3 acc = vec3(0.0);
    float wsum = 0.0;

    float w = 1.0;
    for (int i = 0; i < SAMPLES; i++) {
        float t = time - float(i) * dt;
        acc += drawing_color(uv, t) * w;
        wsum += w;
        w *= decay;
    }

    vec3 col = acc / max(wsum, 1e-6);

    // black background, subtle vignette
    float vig = smoothstep(1.0, 0.2, length(uv));
    col *= (0.65 + 0.35 * vig);

    // optional tiny contrast curve (still dark)
    col = pow(col, vec3(1.10));

    outColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}

void main() {
    vec2 fragCoord = v_uv * iResolution.xy;
    mainImage(fragColor, fragCoord);
}
"""
pass1 = ctx.program(vertex_shader=FSQ_VERT, fragment_shader=PASS1_FRAG)

# ============================================================
# PASS 2: Upscale blit
# ============================================================
PASS2_FRAG = r"""
#version 330
uniform sampler2D src;
in vec2 v_uv;
out vec4 fragColor;
void main() {
    fragColor = vec4(texture(src, v_uv).rgb, 1.0);
}
"""
pass2 = ctx.program(vertex_shader=FSQ_VERT, fragment_shader=PASS2_FRAG)
pass2["src"].value = 0

vao1 = ctx.vertex_array(pass1, [(vbo, "2f 2f", "in_pos", "in_uv")])
vao2 = ctx.vertex_array(pass2, [(vbo, "2f 2f", "in_pos", "in_uv")])

# -----------------------------
# Low-res render target
# -----------------------------
tex = ctx.texture(INTERNAL_RES, components=4, dtype="f1")  # RGBA8
tex.filter = (moderngl.NEAREST, moderngl.NEAREST) if USE_NEAREST else (moderngl.LINEAR, moderngl.LINEAR)
fbo = ctx.framebuffer(color_attachments=[tex])

# Constant uniforms
pass1["iResolution"].value = (float(INTERNAL_RES[0]), float(INTERNAL_RES[1]), 1.0)

clock = pg.time.Clock()
win_w, win_h = WINDOW_RES

while True:
    for e in pg.event.get():
        if e.type == pg.QUIT:
            pg.quit()
            sys.exit()
        if e.type == pg.KEYDOWN and e.key == pg.K_ESCAPE:
            pg.quit()
            sys.exit()
        if e.type == pg.VIDEORESIZE:
            win_w, win_h = e.w, e.h
            try:
                pg.display.set_mode((win_w, win_h), pg.OPENGL | pg.DOUBLEBUF | pg.RESIZABLE, vsync=0)
            except TypeError:
                pg.display.set_mode((win_w, win_h), pg.OPENGL | pg.DOUBLEBUF | pg.RESIZABLE)

    t = pg.time.get_ticks() * 0.001

    # ---- Pass 1: render shader at low res ----
    fbo.use()
    ctx.viewport = (0, 0, INTERNAL_RES[0], INTERNAL_RES[1])
    pass1["iTime"].value = t
    vao1.render(mode=moderngl.TRIANGLE_STRIP)

    # ---- Pass 2: upscale to screen ----
    ctx.screen.use()
    ctx.viewport = (0, 0, win_w, win_h)
    tex.use(location=0)
    vao2.render(mode=moderngl.TRIANGLE_STRIP)

    pg.display.flip()
    clock.tick(FPS_CAP) if FPS_CAP > 0 else clock.tick(0)
