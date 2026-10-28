// 🚨HOW A CAMERA LENS BLUR READS THE LIGHT IT SPREADS (`LensLight`), for
// the two programs that read it: the row sums read every pixel of the
// step's picture so (`row_sum.frag`, its first pass), and the iris reads
// the paper's edge pixels so and puts what it draws back as a picture is
// stored (`iris_gather.frag`). ⛔ONE COPY: a pixel the sums read one way
// and the edge another would seam where the paper ends.
//
// A light is a vec4: its gain, its threshold (0…1), its saturation (0…1),
// and 1 where it reads in linear light, 0 where as the picture is stored.
//
// 📐THE FORMS ARE OURS (🗣️I-132-Q4 b); Adobe's help (read 2026-10-28) says
// what each does. LINEAR: sRGB's own curve, each way. THE HIGHLIGHT: a
// pixel whose brightness — Rec. 709's luma, in the light it is read in —
// lies past the threshold gains `gain · (luma - threshold)` times its luma
// more — the help's: the further past it, the more it is boosted; the
// gain is its own colour by the saturation and white by the rest — the
// help's: none pushes it toward white — both as bright as each other.
// ⛔NO EARLY RETURN (`colour_key.frag`, flutter#190809).

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

vec3 linearOf(vec3 encoded) {
  return mix(
      encoded / 12.92,
      pow((encoded + 0.055) / 1.055, vec3(2.4)),
      step(0.04045, encoded));
}

vec3 storedOf(vec3 rgb) {
  vec3 light = max(rgb, 0.0);
  return mix(
      light * 12.92,
      1.055 * pow(light, vec3(1.0 / 2.4)) - 0.055,
      step(0.0031308, light));
}

// A premultiplied pixel as the blur sums it.
vec4 lit(vec4 pixel, vec4 light) {
  vec3 colour = pixel.a > 0.0 ? pixel.rgb / pixel.a : vec3(0.0);
  if (light.w > 0.5) {
    colour = linearOf(colour);
  }
  float luma = dot(colour, kLuma);
  vec3 tint = mix(vec3(1.0), colour / max(luma, 1e-6), light.z);
  colour += luma * light.x * max(luma - light.y, 0.0) * tint;
  return vec4(colour * pixel.a, pixel.a);
}

// What the blur gathered, as a premultiplied pixel a picture stores: no
// brighter than white, no colour past its alpha.
//
// ⚠️LIGHT PAST ITS ALPHA COVERS (🗣️I-132-Q20 a, 유저 2026-10-28: 「넘친 빛이
// 덮임이 된다 — 투명한 셀 위에서도 보케가 보인다」):
// a boost spread over what is clear is more light than its alpha holds,
// so it is coverage up to the brightest channel's — a lamp's bokeh shows
// over a clear cel as it does over a dark one. A gather of no boost holds
// no channel past its alpha, and is kept as it is.
vec4 stored(vec4 gathered, vec4 light) {
  vec3 rgb = max(gathered.rgb, 0.0);
  float brightest = max(max(rgb.r, rgb.g), rgb.b);
  float alpha = clamp(max(gathered.a, brightest), 0.0, 1.0);
  vec3 colour = alpha > 0.0 ? rgb / alpha : vec3(0.0);
  if (light.w > 0.5) {
    colour = storedOf(colour);
  }
  return vec4(clamp(colour, 0.0, 1.0) * alpha, alpha);
}
