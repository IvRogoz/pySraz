import sys
import pygame as pg
import moderngl
import numpy as np

# -----------------------------
# Settings (SPEED KNOBS)
# -----------------------------
WINDOW_RES   = (1280, 720)
INTERNAL_RES = (320, 180)      # faster: (256,144) or (200,112) | nicer: (480,270)
USE_NEAREST  = False           # True = faster/pixelated, False = smoother
FPS_CAP      = 0               # 0 = uncapped, 60 = cap

# -----------------------------
# Pygame / GL init
# -----------------------------
pg.init()
pg.display.gl_set_attribute(pg.GL_CONTEXT_MAJOR_VERSION, 3)
pg.display.gl_set_attribute(pg.GL_CONTEXT_MINOR_VERSION, 3)
pg.display.gl_set_attribute(pg.GL_CONTEXT_PROFILE_MASK, pg.GL_CONTEXT_PROFILE_CORE)
pg.display.gl_set_attribute(pg.GL_DOUBLEBUFFER, 1)

try:
    screen = pg.display.set_mode(WINDOW_RES, pg.OPENGL | pg.DOUBLEBUF, vsync=0)
except TypeError:
    screen = pg.display.set_mode(WINDOW_RES, pg.OPENGL | pg.DOUBLEBUF)

pg.display.set_caption("Shaderbox shader (wrapped) - low-res FBO")

# -----------------------------
# ModernGL context
# -----------------------------
try:
    ctx = moderngl.create_context(require=330)
except TypeError:
    ctx = moderngl.create_context()

# -----------------------------
# Fullscreen quad
# -----------------------------
quad = np.array([
    -1.0, -1.0,
     1.0, -1.0,
    -1.0,  1.0,
     1.0,  1.0,
], dtype="f4")
vbo = ctx.buffer(quad.tobytes())

VERT = r"""
#version 330
in vec2 in_pos;
void main() {
    gl_Position = vec4(in_pos, 0.0, 1.0);
}
"""

# -----------------------------
# Your Shaderbox/Shadertoy fragment (wrapped for GLSL 330)
# - Provides: iTime, iResolution
# - Calls mainImage(fragColor, fragCoord)
# - FIX: initialize i=0, t=0 so it's deterministic
# -----------------------------
FRAG = r"""
#version 330
uniform float iTime;
uniform vec3  iResolution;   // (w, h, 1)
out vec4 fragColor;

#define C(U) cos(cos(U*i + t) + cos(U.yx*i) + (o.x + t)*i*i)/i/9.

void mainImage( out vec4 o, vec2 u )
{
    u = 4.*(u+u-(o.xy=iResolution.xy))/o.y;
    float t, i, d = dot(u,u);

    // IMPORTANT: make deterministic (avoid uninitialized i/t)
    i = 0.0;
    t = 0.0;

    u /= 1. + .013*d;

    for (o = vec4(.1,.4,.6,0); i++ < 19.;
         o += cos(u.x + i + o.y*9. + t)/4./i)
        t = iTime/2./i,
        u += C(u) + C(u.yx),
        u *= 1.17*mat2(cos(i + length(u)*.3/i
                             - t/2.
                             + vec4(0,11,33,0)));

    o = 1. + cos(o*3. + vec4(8,2,1.8,0));
    o = 1.1 - exp(-1.3*o*sqrt(o))
      + d*min(.02, 4e-6/exp(.2*u.y));
}

void main() {
    // Shadertoy-style pixel coords
    vec2 fragCoord = gl_FragCoord.xy;
    mainImage(fragColor, fragCoord);
}
"""

prog = ctx.program(vertex_shader=VERT, fragment_shader=FRAG)
vao = ctx.vertex_array(prog, [(vbo, "2f", "in_pos")])

# -----------------------------
# Low-res render target
# -----------------------------
tex = ctx.texture(INTERNAL_RES, components=3, dtype="f1")  # 8-bit RGB
tex.filter = (moderngl.NEAREST, moderngl.NEAREST) if USE_NEAREST else (moderngl.LINEAR, moderngl.LINEAR)
fbo = ctx.framebuffer(color_attachments=[tex])

# Uniform locations (guarded)
has_iTime = "iTime" in prog
has_iRes  = "iResolution" in prog

# -----------------------------
# Fallback blit shader (only if fbo.blit/copy_to not available)
# -----------------------------
BLIT_VERT = r"""
#version 330
in vec2 in_pos;
out vec2 v_uv;
void main() {
    v_uv = in_pos * 0.5 + 0.5;
    gl_Position = vec4(in_pos, 0.0, 1.0);
}
"""
BLIT_FRAG = r"""
#version 330
uniform sampler2D src;
in vec2 v_uv;
out vec4 fragColor;
void main() {
    fragColor = vec4(texture(src, v_uv).rgb, 1.0);
}
"""
blit_prog = ctx.program(vertex_shader=BLIT_VERT, fragment_shader=BLIT_FRAG)
blit_prog["src"].value = 0
blit_vao = ctx.vertex_array(blit_prog, [(vbo, "2f", "in_pos")])

def present():
    # Newer ModernGL
    if hasattr(fbo, "copy_to"):
        fbo.copy_to(ctx.screen)
        return

    # Older ModernGL
    if hasattr(fbo, "blit"):
        try:
            fbo.blit(ctx.screen)
            return
        except TypeError:
            pass
        try:
            fbo.blit(ctx.screen, viewport=(0, 0, WINDOW_RES[0], WINDOW_RES[1]))
            return
        except TypeError:
            pass
        try:
            fbo.blit()
            return
        except TypeError:
            pass

    # Worst-case fallback: second pass textured quad
    ctx.screen.use()
    ctx.viewport = (0, 0, WINDOW_RES[0], WINDOW_RES[1])
    tex.use(location=0)
    blit_vao.render(mode=moderngl.TRIANGLE_STRIP)

# -----------------------------
# Main loop
# -----------------------------
clock = pg.time.Clock()

while True:
    for e in pg.event.get():
        if e.type == pg.QUIT:
            pg.quit()
            sys.exit()
        if e.type == pg.KEYDOWN and e.key == pg.K_ESCAPE:
            pg.quit()
            sys.exit()

    t = pg.time.get_ticks() * 0.001

    # Render into low-res FBO
    fbo.use()
    ctx.viewport = (0, 0, INTERNAL_RES[0], INTERNAL_RES[1])

    if has_iTime:
        prog["iTime"].value = t
    if has_iRes:
        prog["iResolution"].value = (float(INTERNAL_RES[0]), float(INTERNAL_RES[1]), 1.0)

    vao.render(mode=moderngl.TRIANGLE_STRIP)

    # Present to screen
    present()

    pg.display.flip()
    if FPS_CAP > 0:
        clock.tick(FPS_CAP)
    else:
        clock.tick(0)
