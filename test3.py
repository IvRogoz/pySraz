import sys
import pygame as pg
import moderngl
import numpy as np

# -----------------------------
# Settings
# -----------------------------
WINDOW_RES   = (1280, 720)
INTERNAL_RES = (320, 180)      # drop for speed: (256,144) or (200,112)
USE_NEAREST  = True           # True = pixelated + slightly faster
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

pg.display.set_caption("Colorful smoke waves (low-res) + upscale (2-pass)")

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
# PASS 1: Colorful smoke shader (low-res)
# ============================================================
PASS1_FRAG = r"""
#version 330
uniform float iTime;
uniform vec3  iResolution;   // (w, h, 1)
in vec2 v_uv;
out vec4 fragColor;

#define TAU 6.28318530718
#define MAX_ITER 8

vec3 palette(float t, vec3 a, vec3 b, vec3 c, vec3 d)
{
    return a + b * cos(6.28318 * (c * t + d));
}

void mainImage(out vec4 outColor, in vec2 fragCoord)
{
    float time = iTime * 0.095 + 23.0;

    vec2 uv = fragCoord / iResolution.xy;

    vec2 p = mod(uv * TAU, TAU) - 213.0;
    vec2 i = p;
    float c = 1.0;
    float inten = 0.005;

    for (int n = 0; n < MAX_ITER; n++) {
        float t = time * (1.0 - (3.5 / float(n + 1)));
        i = p + vec2(cos(t - i.x) + sin(t + i.y),
                     sin(t - i.y) + cos(t + i.x));
        c += 1.0 / length(vec2(
            p.x / (sin(i.x + t) / inten),
            p.y / (cos(i.y + t) / inten)
        ));
    }

    c /= float(MAX_ITER);
    c = 1.17 - pow(c, 1.4);

    vec3 colour = vec3(pow(abs(c), 10.0));
    colour *= 1.1;
    colour = clamp(colour + vec3(0.095), 0.0, 1.0);

    float palettePhase = abs(sin(uv.x * uv.y + iTime * 0.05)) + iTime * 0.1;
    vec3 col = palette(
        palettePhase,
        vec3(0.5, 0.5, 0.5),
        vec3(0.5, 0.5, 0.5),
        vec3(2.0, 1.0, 0.0),
        vec3(0.50, 0.20, 0.25)
    );

    col *= colour;

    outColor = vec4(col, 1.0);
}

void main() {
    // IMPORTANT: use v_uv so in_uv is NOT optimized away
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
