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

pg.display.set_caption("Ice & Fire triangulation (low-res) + upscale (2-pass)")

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
# PASS 1: Ice and fire shader (low-res)
# ============================================================
PASS1_FRAG = r"""
#version 330
uniform float iTime;
uniform vec3  iResolution;   // (w, h, 1)
in vec2 v_uv;
out vec4 fragColor;

/* ice and fire, by mattz
   License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.

   Demonstrate triangulation of jittered triangular lattice.
*/
const float s3 = 1.7320508075688772;
const float i3 = 0.5773502691896258;

const mat2 tri2cart = mat2(1.0, 0.0, -0.5, 0.5*s3);
const mat2 cart2tri = mat2(1.0, 0.0, i3, 2.0*i3);

//////////////////////////////////////////////////////////////////////
// cosine based palette
// adapted from https://www.shadertoy.com/view/ll2GD3

vec3 pal( in float t ) {

    const vec3 a = vec3(0.5);
    const vec3 b = vec3(0.5);
    const vec3 c = vec3(0.8, 0.8, 0.5);
    const vec3 d = vec3(0, 0.2, 0.5);

    return clamp(a + b*cos( 6.28318*(c*t+d) ), 0.0, 1.0);

}

//////////////////////////////////////////////////////////////////////
// from https://www.shadertoy.com/view/4djSRW

#define HASHSCALE1 .1031
#define HASHSCALE3 vec3(443.897, 441.423, 437.195)

float hash12(vec2 p) {
    vec3 p3  = fract(vec3(p.xyx) * HASHSCALE1);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash23(vec3 p3) {
    p3 = fract(p3 * HASHSCALE3);
    p3 += dot(p3, p3.yzx+19.19);
    return fract((p3.xx+p3.yz)*p3.zy);
}

//////////////////////////////////////////////////////////////////////
// compute barycentric coordinates from point differences
// adapted from https://www.shadertoy.com/view/lslXDf

vec3 bary(vec2 v0, vec2 v1, vec2 v2) {
    float inv_denom = 1.0 / (v0.x * v1.y - v1.x * v0.y);
    float v = (v2.x * v1.y - v1.x * v2.y) * inv_denom;
    float w = (v0.x * v2.y - v2.x * v0.y) * inv_denom;
    float u = 1.0 - v - w;
    return vec3(u,v,w);
}

//////////////////////////////////////////////////////////////////////
// distance to line segment from point differences

float dseg(vec2 xa, vec2 ba) {
    return length(xa - ba*clamp(dot(xa, ba)/dot(ba, ba), 0.0, 1.0));
}

//////////////////////////////////////////////////////////////////////
// generate a random point on a circle from 3 integer coords (x, y, t)

vec2 randCircle(vec3 p) {

    vec2 rt = hash23(p);

    float r = sqrt(rt.x);
    float theta = 6.283185307179586 * rt.y;

    return r*vec2(cos(theta), sin(theta));

}

//////////////////////////////////////////////////////////////////////
// make a time-varying cubic spline at integer coords p that stays
// inside a unit circle

vec2 randCircleSpline(vec2 p, float t) {

    // standard catmull-rom spline implementation
    float t1 = floor(t);
    t -= t1;

    vec2 pa = randCircle(vec3(p, t1-1.0));
    vec2 p0 = randCircle(vec3(p, t1));
    vec2 p1 = randCircle(vec3(p, t1+1.0));
    vec2 pb = randCircle(vec3(p, t1+2.0));

    vec2 m0 = 0.5*(p1 - pa);
    vec2 m1 = 0.5*(pb - p0);

    vec2 c3 = 2.0*p0 - 2.0*p1 + m0 + m1;
    vec2 c2 = -3.0*p0 + 3.0*p1 - 2.0*m0 - m1;
    vec2 c1 = m0;
    vec2 c0 = p0;

    return (((c3*t + c2)*t + c1)*t + c0) * 0.8;

}

//////////////////////////////////////////////////////////////////////
// perturbed point from index

vec2 triPoint(vec2 p) {
    float t0 = hash12(p);
    return tri2cart*p + 0.45*randCircleSpline(p, 0.15*iTime + t0);
}

//////////////////////////////////////////////////////////////////////
// main shading function.

void tri_color(in vec2 p,
               in vec4 t0, in vec4 t1, in vec4 t2,
               in float scl,
               inout vec4 cw) {

    // get differences relative to vertex 0
    vec2 p0 = p - t0.xy;
    vec2 p10 = t1.xy - t0.xy;
    vec2 p20 = t2.xy - t0.xy;

    // get barycentric coords
    vec3 b = bary(p10, p20, p0);

    // distances to line segments
    float d10 = dseg(p0, p10);
    float d20 = dseg(p0, p20);
    float d21 = dseg(p - t1.xy, t2.xy - t1.xy);

    // unsigned distance to triangle boundary
    float d = min(min(d10, d20), d21);

    // now signed distance (negative inside, positive outside)
    d *= -sign(min(b.x, min(b.y, b.z)));

    // only worry about coloring if close enough
    if (d < 0.5*scl) {

        // sum of all integer grid indices
        vec2 tsum = t0.zw + t1.zw + t2.zw;

        // unique random number in [0, 1] for each vertex
        vec3 h_tri = vec3(hash12(tsum + t0.zw),
                          hash12(tsum + t1.zw),
                          hash12(tsum + t2.zw));

        // centroid
        vec2 pctr = (t0.xy + t1.xy + t2.xy) / 3.0;

        // angle of scene-wide gradient
        float theta = 1.0 + 0.01*iTime;
        vec2 dir = vec2(cos(theta), sin(theta));

        float grad_input = dot(pctr, dir) - sin(0.05*iTime);

        float h0 = sin(0.7*grad_input)*0.5 + 0.5;

        h_tri = mix(vec3(h0), h_tri, 0.4);

        float h = dot(h_tri, b);

        vec3 c = pal(h);

        float w = smoothstep(0.5*scl, -0.5*scl, d);

        cw += vec4(w*c, w);

    }

}

//////////////////////////////////////////////////////////////////////

void mainImage( out vec4 outColor, in vec2 fragCoord ) {

    float scl = 4.1 / iResolution.y;

    // 2D scene coords
    vec2 p = (fragCoord - 0.5 - 0.5*iResolution.xy) * scl;

    vec2 tfloor = floor(cart2tri * p + 0.5);

    // precompute 9 neighboring points
    vec2 pts[9];
    for (int ii=0; ii<3; ++ii) {
        for (int jj=0; jj<3; ++jj) {
            pts[3*ii+jj] = triPoint(tfloor + vec2(ii-1, jj-1));
        }
    }

    vec4 cw = vec4(0);

    // for each of the 4 quads:
    for (int ii=0; ii<2; ++ii) {
        for (int jj=0; jj<2; ++jj) {

            vec4 t00 = vec4(pts[3*ii+jj  ], tfloor + vec2(ii-1, jj-1));
            vec4 t10 = vec4(pts[3*ii+jj+3], tfloor + vec2(ii,   jj-1));
            vec4 t01 = vec4(pts[3*ii+jj+1], tfloor + vec2(ii-1, jj));
            vec4 t11 = vec4(pts[3*ii+jj+4], tfloor + vec2(ii,   jj));

            // lower
            tri_color(p, t00, t10, t11, scl, cw);

            // upper
            tri_color(p, t00, t11, t01, scl, cw);
        }
    }

    outColor = cw / cw.w;
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
