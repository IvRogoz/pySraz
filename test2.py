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

pg.display.set_caption("Procedural shader (low-res) + upscale (2-pass)")

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
# PASS 1: YOUR PROCEDURAL SHADER (low-res)
# ============================================================
PASS1_FRAG = r"""
#version 330
uniform float iTime;
uniform vec3  iResolution;   // (w, h, 1)
in vec2 v_uv;
out vec4 fragColor;

float hash21( in vec2 p )
{
    p = 50.0*fract( p*0.3183099 + vec2(0.71,0.113));
    return fract( p.x*p.y*(p.x+p.y) );
}

vec2 hash22( in vec2 p )
{
    return vec2(hash21(p.xy+vec2(0.0,0.0)),
                hash21(p.yx+vec2(0.7,0.5)));
}

float noise( in vec2 x )
{
    vec2 i = floor(x);
    vec2 f = fract(x);
    f = f*f*(3.0-2.0*f);
    float a = hash21(i+vec2(0,0));
    float b = hash21(i+vec2(1,0));
    float c = hash21(i+vec2(0,1));
    float d = hash21(i+vec2(1,1));
    return -1.0+2.0*mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}

float voronoi( in vec2 p )
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    float d = 10.0;
    for( int n=-1; n<=1; n++ )
    for( int m=-1; m<=1; m++ )
    {
        vec2 b = vec2(m, n);
        vec2 r = b - f + hash22(i+b);
        d = min(d,dot(r,r));
    }
    return d;
}

float fbmNoise( in vec2 p, in int oct )
{
    const mat2 m = mat2( 0.8, 0.6, -0.6, 0.8 );

    float f = 0.0;
    float s = 0.5;
    float t = 0.0;
    for( int i=0; i<oct; i++ )
    {
        f += s*noise( p );
        t += s;
        p = m*p*2.01;
        s *= 0.5;
    }
    return f/t;
}

float fbmVoronoi( in vec2 p )
{
    float f = 1.0;
    float s = 1.0;
    for( int i=0; i<8; i++ )
    {
        float v = voronoi(p);
        f = min(f,v*s);
        p *= 2.0;
        s *= 1.4;
    }
    return 3.0*f;
}

vec2 fbm2Noise( in vec2 p, in int o )
{
    return vec2(fbmNoise(p.xy+vec2(0.0,0.0),o),
                fbmNoise(p.yx+vec2(0.7,1.3),o));
}

// distortion
vec2 dis( in vec2 p, in float t )
{
    // scroll
    p.x -= 0.2*t;

    // whirl
    const float a = 1.6;
    const float b = 0.5;
    float j = 1.0;
    do {
        p += a*(b/j)*sin(p.yx*pow(2.0, j-1.0)+(j/10.0)+(j-1.0)+t);
        j += 1.0;
    } while (j < 4.0);

    // turbulence
    p += 0.4*fbm2Noise(0.5*p-t*vec2(0.9,0.0), 2);

    return p;
}

void mainImage(out vec4 outColor, in vec2 fragCoord)
{
    const vec3 col1 = vec3(0.0, 0.01, 0.05);
    const vec3 col2 = vec3(0.6, 0.0, 0.1);
    const float spd = 0.01;
    const float disSpd = 0.05;

    float time = iTime + 160.0; // skip ahead in time

    vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;
    uv *= 2.0;                 // detail/zoom
    uv = dis(uv, time*disSpd); // distortion

    float n = ceil(
        fbmNoise(uv - time*spd, 4) -
        fbmNoise(uv + time*spd, 4) -
        0.5*fbmVoronoi(uv*0.3)
    );
    n = clamp(n, 0.0, 1.0);

    vec3 color = mix(col1, col2, n);
    outColor = vec4(color, 1.0);
}

void main() {
    // IMPORTANT: use v_uv so in_uv is NOT optimized away
    vec2 fragCoord = v_uv * iResolution.xy;
    mainImage(fragColor, fragCoord);
}
"""
pass1 = ctx.program(vertex_shader=FSQ_VERT, fragment_shader=PASS1_FRAG)

# ============================================================
# PASS 2: UPSCALE BLIT
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

    # ---- Pass 1: render procedural shader at low res ----
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
