-- src/shader_galaxy.lua
local Shader = {}

Shader.GALAXY_SHADER = [[
extern float iTime;
extern vec3  iResolution;
extern Image iChannel0;

float field(vec3 p, float s) {
  float strength = 7. + .03 * log(1.e-6 + fract(sin(iTime) * 4373.11));
  float accum = s/4.;
  float prev = 0.;
  float tw = 0.;
  for (int i = 0; i < 26; ++i) {
    float mag = dot(p, p);
    p = abs(p) / mag + vec3(-.5, -.4, -1.5);
    float w = exp(-float(i) / 7.);
    accum += w * exp(-strength * pow(abs(mag - prev), 2.2));
    tw += w;
    prev = mag;
  }
  return max(0., 5. * accum / tw - .7);
}

float field2(vec3 p, float s) {
  float strength = 7. + .03 * log(1.e-6 + fract(sin(iTime) * 4373.11));
  float accum = s/4.;
  float prev = 0.;
  float tw = 0.;
  for (int i = 0; i < 18; ++i) {
    float mag = dot(p, p);
    p = abs(p) / mag + vec3(-.5, -.4, -1.5);
    float w = exp(-float(i) / 7.);
    accum += w * exp(-strength * pow(abs(mag - prev), 2.2));
    tw += w;
    prev = mag;
  }
  return max(0., 5. * accum / tw - .7);
}

vec3 nrand3(vec2 co) {
  vec3 a = fract( cos( co.x*8.3e-3 + co.y )*vec3(1.3e5, 4.7e5, 2.9e5) );
  vec3 b = fract( sin( co.x*0.3e-3 + co.y )*vec3(8.1e5, 1.0e5, 0.1e5) );
  return mix(a, b, 0.5);
}

vec4 effect(vec4 color, Image base, vec2 tc, vec2 sc) {
  vec4 baseColor = Texel(base, tc);

  vec2 fragCoord = sc;
  vec2 uv = 2. * fragCoord.xy / iResolution.xy - 1.;
  vec2 uvs = uv * iResolution.xy / max(iResolution.x, iResolution.y);

  vec3 p = vec3(uvs / 4., 0.) + vec3(1., -1.3, 0.);
  p += .2 * vec3(sin(iTime / 16.), sin(iTime / 12.),  sin(iTime / 128.));

  float freqs0 = Texel(iChannel0, vec2(0.01, 0.25)).r;
  float freqs1 = Texel(iChannel0, vec2(0.07, 0.25)).r;
  float freqs2 = Texel(iChannel0, vec2(0.15, 0.25)).r;
  float freqs3 = Texel(iChannel0, vec2(0.30, 0.25)).r;

  float bass = pow(freqs0, 0.6);
  float mid  = pow(freqs1, 0.8);
  float hi   = pow(freqs3, 0.9);

  float t = field(p, freqs2 + 0.08 + 0.35 * mid);
  float v = (1. - exp((abs(uv.x) - 1.) * 6.)) * (1. - exp((abs(uv.y) - 1.) * 6.));

  vec3 p2 = vec3(uvs / (4.+sin(iTime*0.11)*0.2+0.2+sin(iTime*0.15)*0.3+0.4), 1.5) + vec3(2., -1.3, -1.);
  p2 += 0.25 * vec3(sin(iTime / 16.), sin(iTime / 12.),  sin(iTime / 128.));
  float t2 = field2(p2, freqs3 + 0.10 + 0.45 * hi);

  vec4 c2 = mix(.4, 1., v) * vec4(1.3 * t2 * t2 * t2,
                                  1.8 * t2 * t2,
                                  t2 * (freqs0 + 0.15 + 0.6*bass),
                                  1.0);

  vec2 seed = p.xy * 2.0;
  seed = floor(seed * iResolution.x);
  vec3 rnd = nrand3(seed);
  vec4 starcolor = vec4(pow(rnd.y,40.0));

  vec2 seed2 = p2.xy * 2.0;
  seed2 = floor(seed2 * iResolution.x);
  vec3 rnd2 = nrand3(seed2);
  starcolor += vec4(pow(rnd2.y,40.0));

  vec4 col = mix(freqs3-.3, 1., v) * vec4(1.5*freqs2 * t * t* t ,
                                          1.2*freqs1 * t * t,
                                          freqs3*t, 1.0)
            + c2 + starcolor;

  col.a = 1.0;
  return col;
}
]]

return Shader
