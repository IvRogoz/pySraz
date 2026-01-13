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

pg.display.set_caption("Layered lines shader (low-res) + upscale (2-pass)")

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
# PASS 1: Your layered-lines shader (low-res)
# ============================================================
PASS1_FRAG = r"""
#version 330
uniform float iTime;
uniform vec3  iResolution;   // (w, h, 1)
in vec2 v_uv;
out vec4 fragColor;

#define BackgroundColor vec3(0.91765, 0.88627, 0.82745)
#define Layer1Color vec3(0.95686, 0.27451, 0.16078)
#define Layer2Color vec3(0.10980, 0.12157, 0.27843)
#define Layer3Color vec3(0.18824, 0.20000, 0.52157)

#define degToRad 0.01745329252

float Rand(float i)
{
    return fract(sin(i * 23325.) * 35543.);
}

vec4 Rand4(float i)
{
    return fract(sin(i * vec4(23325.,53464.,76543.,12312)) * vec4(35543.,63454.,23454.,87651));
}

mat2 Rot(float a)
{
    float s = sin(a);
    float c = cos(a);
    return mat2(c, -s, s, c);
}

float DrawLine(in vec2 uv, in vec2 a, in vec2 b )
{
    vec2 ba = b-a;
    vec2 pa = uv-a;
    float h = clamp(dot(pa,ba)/dot(ba,ba), 0.0, 1.0);
    return length(pa - h*ba);
}

float DrawLineSegment(in vec2 uv, float linesCount, float speed, float verticalAmplitude, float segmentSeed)
{
    float segmentMask = 0.0;

    float iterationStep = 1.0 / linesCount;
    float t = iTime * speed * 0.1;

    float horizontalAmplitude = 3.5;
    vec2 lineWidthRange = vec2(0.2, 1.5);
    vec2 lineSizeRange  = vec2(0.005, 0.035);

    float seedBase = Rand(segmentSeed);

    // NOTE: float loop with i += iterationStep is fine on many drivers,
    // but to be safer we use an integer loop and compute i ourselves.
    int N = int(linesCount);
    for (int k = 0; k <= 512; k++) {
        if (k > N) break;
        float i = float(k) / max(linesCount, 1.0);

        float unitSpeed = mix(0.5, 2.0, Rand(i));
        float seed = t * unitSpeed + i + seedBase;
        float it = fract(seed);
        vec4 iHash = Rand4(i);

        float normit = it * 2.0 - 1.0;

        float lineWidth = mix(lineWidthRange.x, lineWidthRange.y, pow(iHash.y, 2.0));

        vec2 ap = vec2(-horizontalAmplitude * normit, iHash.x * verticalAmplitude);
        vec2 bp = ap + vec2(lineWidth, 0.0);

        float lineSegmentDist = DrawLine(uv, ap, bp);

        float lineSize = mix(lineSizeRange.x, lineSizeRange.y, pow(iHash.z, 4.0));

        segmentMask += smoothstep(lineSize + 0.002, lineSize - 0.002, lineSegmentDist);
    }

    return clamp(segmentMask, 0.0, 1.0);
}

void mainImage(out vec4 outColor, in vec2 fragCoord)
{
    vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;

    uv *= Rot(degToRad * -35.0);

    vec3 col = mix(Layer1Color, BackgroundColor, smoothstep(-0.055, -0.05, uv.y));
    col = mix(Layer2Color, col, smoothstep(-0.655, -0.65, uv.y));
    col = mix(Layer3Color, col, smoothstep(-1.305, -1.3, uv.y));

    col = mix(col, BackgroundColor, DrawLineSegment(uv - vec2(0.0, -0.3),  9.0,  0.5, 0.35, 0.2));
    col = mix(col, Layer1Color,     DrawLineSegment(uv - vec2(0.0,  0.0), 25.0, -0.4, 0.50, 0.1));

    col = mix(col, Layer1Color,     DrawLineSegment(uv - vec2(0.0, -1.0), 25.0, -0.4, 0.45, 0.4));
    col = mix(col, Layer2Color,     DrawLineSegment(uv - vec2(0.0, -0.65),25.0,  0.3, 0.30, 0.3));

    col = mix(col, Layer2Color,     DrawLineSegment(uv - vec2(0.0, -1.8), 25.0,  0.3, 0.55, 0.6));
    col = mix(col, Layer3Color,     DrawLineSegment(uv - vec2(0.0, -1.3), 25.0, -0.2, 0.30, 0.5));

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
