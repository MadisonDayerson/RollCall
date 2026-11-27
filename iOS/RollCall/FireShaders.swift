/// The splash's fire, in Metal. It's kept as text and compiled as RollCall opens, so building RollCall doesn't need
/// Xcode's separate Metal download. Places are in points from the top left, and speeds in points a second.
enum FireShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    /// The same as `Fire.Now`.
    struct Now {
        float2 size;      // of the screen
        float2 middle;    // of the letters
        float4 logo;      // where their picture is: x, y, width, height
        float2 across;    // the letters' left and right
        float2 down;      // and their top and bottom
        float cell;       // the side of one cell of air
        float time, dt;
        float ground;     // the black behind it all, 0 to 1
        uint embers;
    };

    /// The same as `Fire.Ember`. Kept in a buffer, and moved by `moveEmbers`.
    struct Ember {
        float2 place, speed;
        float radius, depth, heat, seed;
    };

    constexpr sampler smooth(filter::linear, mip_filter::linear, address::clamp_to_edge);
    constexpr sampler bare(filter::linear, address::clamp_to_zero);

    // MARK: Noise

    float hash(float2 p) {
        float3 q = fract(float3(p.xyx) * 0.1031);
        q += dot(q, q.yzx + 33.33);
        return fract((q.x + q.y) * q.z);
    }

    float noise(float2 p) {
        float2 i = floor(p), f = p - i;
        f = f * f * f * (f * (f * 6 - 15) + 10);
        return mix(mix(hash(i), hash(i + float2(1, 0)), f.x), mix(hash(i + float2(0, 1)), hash(i + 1), f.x), f.y);
    }

    float clouds(float2 p) {
        float sum = 0, part = 0.5;
        for (int i = 0; i < 4; i++) {
            sum += part * noise(p);
            p = float2x2(1.6, 1.2, -1.2, 1.6) * p + 17.3;
            part *= 0.5;
        }
        return sum;
    }

    /// Swirls with nothing gathering or thinning out, like air.
    float2 swirl(float2 p) {
        float e = 0.1;
        float up = clouds(p + float2(0, e)), down = clouds(p - float2(0, e));
        float right = clouds(p + float2(e, 0)), left = clouds(p - float2(e, 0));
        return float2(up - down, left - right) / (2 * e);
    }

    /// The same, but only broad and smooth.
    float2 wave(float2 p) {
        float e = 0.2;
        return float2(noise(p + float2(0, e)) - noise(p - float2(0, e)), noise(p - float2(e, 0)) - noise(p + float2(e, 0))) / (2 * e);
    }

    /// Half the letters' width and height.
    float2 halves(constant Now &now) { return float2(now.across.y - now.across.x, now.down.y - now.down.x) * 0.5; }

    /// Where `p` is from the middle, in halves of the letters' width and height, so the burst keeps to their shape.
    float2 fromMiddle(float2 p, constant Now &now) { return (p - now.middle) / halves(now); }

    /// How far the burst reaches, in those halves, and how long it takes.
    constant float reach = 1.2, bursts = 0.4;

    /// How much further than usual the burst goes the way of `p`, so it's ragged.
    float ragged(float2 p, constant Now &now) {
        float2 way = fromMiddle(p, now);
        return 0.5 + 1.0 * clouds(way / max(length(way), 0.01) * 4 + 11);
    }

    /// How far the burst has got the way of `p`, `t` seconds in: fast, then slowing.
    float front(float2 p, float t, constant Now &now) {
        float k = saturate(t / bursts);
        return reach * ragged(p, now) * (1 - (1 - k) * (1 - k) * (1 - k));
    }

    /// When the burst gets here, and the letters here appear.
    float forms(float2 p, constant Now &now) {
        float k = saturate(length(fromMiddle(p, now)) / (reach * ragged(p, now)));
        return bursts * (1 - pow(1 - k, 1.0 / 3)) + 0.05 * (noise(p * 0.15) - 0.5);
    }

    /// When the bush fire gets here: a ragged front from left to right, a little ahead along the ground.
    float arrives(float2 p, constant Now &now) {
        float along = (p.x - now.across.x) / (now.across.y - now.across.x);
        return \(Fire.wipe) + 0.2 + 0.72 * along + 0.34 * (clouds(p * 0.035) - 0.47) - 0.0008 * (p.y - now.middle.y);
    }

    /// When the letters here have burnt through, so their embers leave as they do.
    float burnsAt(float2 p, constant Now &now) { return arrives(p, now) + 0.13 + 0.07 * noise(p * 0.4); }

    // MARK: Air and fire (x: how hot the flame is, y: warm air)

    kernel void advect(texture2d<float> air [[texture(0)]], texture2d<float> fire [[texture(1)]], texture2d<float> mask [[texture(2)]],
                       texture2d<float, access::write> airOut [[texture(3)]], texture2d<float, access::write> fireOut [[texture(4)]],
                       constant Now &now [[buffer(0)]], uint2 id [[thread_position_in_grid]]) {
        float2 p = (float2(id) + 0.5) * now.cell;
        float2 back = p - air.sample(smooth, p / now.size).xy * now.dt;
        float2 v = air.sample(smooth, back / now.size).xy * exp(-1.2 * now.dt);
        float2 f = fire.sample(bare, back / now.size).xy;

        float letters = mask.sample(smooth, p / now.size, level(1)).x;
        float near = mask.sample(smooth, p / now.size, level(3)).x;
        // The burst: a flash, and a ball of flame thrown out from the middle, brightest at its ragged edge.
        float patchy = smoothstep(0.3, 0.6, clouds(float2(p.x * 0.09 + now.time * 1.5, p.y * 0.05 + now.time * 5)));
        float2 out = p - now.middle;
        float r = length(out), unit = 0.5 * (halves(now).x + halves(now).y);
        float ringed = ((length(fromMiddle(p, now)) - front(p, now.time, now)) * unit + 16 * (noise(p * 0.09 + now.time * 4) - 0.5)) / (6 + 30 * now.time);
        float ring = (exp(-ringed * ringed) + 0.3 * smoothstep(0.0, -1.5, ringed)) * smoothstep(0.7, 0.25, now.time) * (0.35 + 0.9 * patchy);
        float flash = exp(-r * r / ((20 + 500 * now.time) * (20 + 500 * now.time))) * smoothstep(0.2, 0.0, now.time) * 1.6;
        // Still air, with nothing to work out.
        if (f.x + f.y + near + ring + flash < 0.002) {
            airOut.write(float4(v, 0, 0), id);
            fireOut.write(float4(0), id);
            return;
        }

        // Flames cool as they shine.
        f.x = max(0.0, f.x - now.dt * (4.2 + 1.6 * f.x + 5 * smoothstep(0.35, 0.75, clouds(float2(p.x * 0.09, p.y * 0.05 + now.time * 6)))));
        f.y *= exp(-2.2 * now.dt);

        // The letters flare as they appear.
        float born = now.time - forms(p, now);
        float flaring = smoothstep(-0.03, 0.02, born) * smoothstep(0.25, 0.08, born);
        // The air warms ahead of the bush fire, which feeds on the letters until they've burnt through.
        float since = now.time - arrives(p, now);
        float warming = smoothstep(-0.3, 0.0, since) * smoothstep(0.35, 0.1, since);
        float burning = smoothstep(-0.04, 0.02, since) * smoothstep(0.28, 0.16, since);
        f.x = max(f.x, max(letters * (burning * (0.2 + 1.0 * patchy) + flaring * (0.25 + 0.8 * patchy)), ring + flash));
        f.y = min(1.5, f.y + now.dt * (near * warming * 14 + f.x * 5));

        // The burst throws the air out.
        v += now.dt * out / max(r, 1.0) * ring * 6000;
        // Hot air rises, tumbling, and once the bush fire starts a breeze leans it the way it's going.
        float leaning = smoothstep(\(Fire.wipe) - 0.4, \(Fire.wipe), now.time);
        v += now.dt * float2(2100 * f.x * leaning + 110 * f.y, -(1900 * f.x * f.x + 1500 * f.x + 50 * f.y));
        v += now.dt * wave(p * 0.06 + float2(now.time * 1.5, now.time * 6.0)) * (3000 * f.x + 80 * f.y);

        airOut.write(float4(v, 0, 0), id);
        fireOut.write(float4(f, 0, 0), id);
    }

    kernel void spin(texture2d<float> air [[texture(0)]], texture2d<float, access::write> out [[texture(1)]], uint2 id [[thread_position_in_grid]]) {
        uint2 last = uint2(air.get_width() - 1, air.get_height() - 1);
        float2 l = air.read(uint2(max(id.x, 1u) - 1, id.y)).xy, r = air.read(uint2(min(id.x + 1, last.x), id.y)).xy;
        float2 u = air.read(uint2(id.x, max(id.y, 1u) - 1)).xy, d = air.read(uint2(id.x, min(id.y + 1, last.y))).xy;
        out.write(float4(0.5 * ((r.y - l.y) - (d.x - u.x))), id);
    }

    /// Keeps the small curls the grid would smooth away, and works out how much the air is spreading.
    kernel void curl(texture2d<float> air [[texture(0)]], texture2d<float> spins [[texture(1)]],
                     texture2d<float, access::write> out [[texture(2)]], constant Now &now [[buffer(0)]], uint2 id [[thread_position_in_grid]]) {
        uint2 last = uint2(air.get_width() - 1, air.get_height() - 1);
        float l = abs(spins.read(uint2(max(id.x, 1u) - 1, id.y)).x), r = abs(spins.read(uint2(min(id.x + 1, last.x), id.y)).x);
        float u = abs(spins.read(uint2(id.x, max(id.y, 1u) - 1)).x), d = abs(spins.read(uint2(id.x, min(id.y + 1, last.y))).x);
        float2 slope = float2(r - l, d - u);
        slope /= length(slope) + 1e-3;
        float s = spins.read(id).x;
        float2 v = air.read(id).xy + now.dt * 30 * s * float2(slope.y, -slope.x);
        out.write(float4(clamp(v, -1400, 1400), 0, 0), id);
    }

    kernel void spread(texture2d<float> air [[texture(0)]], texture2d<float> fire [[texture(1)]], texture2d<float, access::write> out [[texture(2)]],
                       constant Now &now [[buffer(0)]], uint2 id [[thread_position_in_grid]]) {
        uint2 last = uint2(air.get_width() - 1, air.get_height() - 1);
        float l = air.read(uint2(max(id.x, 1u) - 1, id.y)).x, r = air.read(uint2(min(id.x + 1, last.x), id.y)).x;
        float u = air.read(uint2(id.x, max(id.y, 1u) - 1)).y, d = air.read(uint2(id.x, min(id.y + 1, last.y))).y;
        // Burning gas takes more room.
        float growing = 4 * smoothstep(0.5, 1.2, fire.read(id).x) * now.cell;
        out.write(float4(0.5 * (r - l + d - u) - growing), id);
    }

    kernel void relax(texture2d<float> press [[texture(0)]], texture2d<float> spreads [[texture(1)]], texture2d<float, access::write> out [[texture(2)]],
                      uint2 id [[thread_position_in_grid]]) {
        // Open all round: outside the screen the pressure is 0.
        uint w = press.get_width(), h = press.get_height();
        float l = id.x > 0 ? press.read(id - uint2(1, 0)).x : 0, r = id.x + 1 < w ? press.read(id + uint2(1, 0)).x : 0;
        float u = id.y > 0 ? press.read(id - uint2(0, 1)).x : 0, d = id.y + 1 < h ? press.read(id + uint2(0, 1)).x : 0;
        out.write(float4((l + r + u + d - spreads.read(id).x) * 0.25), id);
    }

    kernel void settle(texture2d<float> air [[texture(0)]], texture2d<float> press [[texture(1)]], texture2d<float, access::write> out [[texture(2)]],
                       uint2 id [[thread_position_in_grid]]) {
        uint w = press.get_width(), h = press.get_height();
        float l = id.x > 0 ? press.read(id - uint2(1, 0)).x : 0, r = id.x + 1 < w ? press.read(id + uint2(1, 0)).x : 0;
        float u = id.y > 0 ? press.read(id - uint2(0, 1)).x : 0, d = id.y + 1 < h ? press.read(id + uint2(0, 1)).x : 0;
        out.write(float4(air.read(id).xy - 0.5 * float2(r - l, d - u), 0, 0), id);
    }

    // MARK: Embers

    kernel void moveEmbers(device const Ember *was [[buffer(0)]], device Ember *is [[buffer(1)]], constant Now &now [[buffer(2)]],
                           texture2d<float> air [[texture(0)]], uint id [[thread_position_in_grid]]) {
        Ember e = was[id];
        float2 wind = air.sample(smooth, e.place / now.size).xy;
        if (e.heat < 0) {  // still part of a letter
            if (now.time < burnsAt(e.place, now)) { is[id] = e; return; }
            float angle = e.seed * 6.2832;
            e.heat = 0.8 + 0.5 * fract(e.seed * 91.7);
            e.speed = wind * 0.5 + float2(cos(angle), sin(angle)) * 110 * fract(e.seed * 71.1) + float2(70, -60) * fract(e.seed * 37.3);
        }
        // Small ones go with the air; heavy ones carry on and fall.
        float follow = 1 / (0.07 + 0.16 * e.radius * e.radius);
        float2 gust = swirl(e.place * 0.014 + float2(e.depth * 5, now.time * 0.45)) * 100 + float2(30 + 130 * fract(e.seed * 17.9), -60 * fract(e.seed * 29.3));
        float2 push = (wind * 0.5 + gust - e.speed) * follow + float2(0, 240 * e.radius);
        // They knock each other away.
        for (uint i = 0; i < now.embers; i++) {
            if (i == id || was[i].heat <= 0) continue;
            float2 apart = e.place - was[i].place;
            float touch = (e.radius + was[i].radius) * 2;
            float d2 = dot(apart, apart);
            if (d2 > touch * touch || d2 < 1e-4 || abs(e.depth - was[i].depth) > 0.15) continue;
            float d = sqrt(d2);
            float2 n = apart / d;
            float share = was[i].radius * was[i].radius / (e.radius * e.radius + was[i].radius * was[i].radius);
            push += n * share * ((touch - d) * 5200 - 14 * dot(e.speed - was[i].speed, n));
        }
        e.speed += clamp(push, -14000, 14000) * now.dt;
        e.speed = clamp(e.speed, -1300, 1300);
        e.place += e.speed * now.dt;
        // And bounce off the screen's edges, losing some of their speed.
        float2 low = float2(e.radius), high = now.size - e.radius;
        if (e.place.x < low.x || e.place.x > high.x) { e.speed *= float2(-0.5, 0.8); }
        if (e.place.y > high.y) { e.speed *= float2(0.75, -0.45); }
        e.place = clamp(e.place, float2(low.x, -200), high);
        // Moving air burns them out sooner; the burst's are out while the letters are read, and all are by the end.
        float fanned = length(wind * 0.5 + gust - e.speed) / 300;
        float ending = 2.5 * smoothstep(0.6, 0.9, now.time) * step(now.time, \(Fire.wipe)) + 1.6 * smoothstep(\(Fire.wipe) + 1.6, \(Fire.wipe) + 2.5, now.time);
        e.heat = max(0.0, e.heat - now.dt * (0.42 + 0.35 * fanned + 0.25 / (0.4 + e.radius) + ending) * (0.75 + 0.5 * fract(e.seed * 53.1)));
        is[id] = e;
    }

    struct EmberPoint {
        float4 position [[position]];
        float2 at;
        float heat, seed, stretch, dim;
    };

    vertex EmberPoint emberPoint(uint corner [[vertex_id]], uint id [[instance_id]], device const Ember *embers [[buffer(0)]],
                                 constant Now &now [[buffer(1)]]) {
        Ember e = embers[id];
        EmberPoint o;
        float2 c = float2(corner & 1, corner >> 1) * 2 - 1;
        // Nearer ones are larger; all of them blur along the way they're going.
        float radius = e.radius * e.depth * (0.45 + 0.55 * smoothstep(0.0, 0.5, e.heat));
        float speed = length(e.speed);
        float2 along = speed > 1 ? e.speed / speed : float2(1, 0), across = float2(-along.y, along.x);
        float reach = radius + speed * e.depth * 0.006;
        float halo = 2.6;
        float2 p = e.place + along * c.x * (reach + radius * (halo - 1)) + across * c.y * radius * halo;
        if (e.heat <= 0) p = float2(-9999);
        o.position = float4(p.x / now.size.x * 2 - 1, 1 - p.y / now.size.y * 2, 0, 1);
        o.at = float2(c.x * (reach / radius + halo - 1), c.y * halo);
        o.stretch = reach / radius - 1;
        o.heat = e.heat;
        o.seed = e.seed;
        o.dim = sqrt(radius / reach);
        return o;
    }

    /// White-blue when hottest, through blue, to a dull deep blue: the splash's one colour.
    float3 glow(float heat) {
        float3 c = mix(float3(0.01, 0.035, 0.16), float3(0.03, 0.2, 1.0), smoothstep(0.0, 0.4, heat));
        c = mix(c, float3(0.25, 0.72, 1.35), smoothstep(0.35, 0.75, heat));
        return mix(c, float3(0.95, 1.25, 1.5), smoothstep(0.75, 1.25, heat));
    }

    fragment float4 emberGlow(EmberPoint in [[stage_in]], constant Now &now [[buffer(0)]]) {
        float flicker = 0.72 + 0.28 * sin(now.time * (18 + 25 * fract(in.seed * 7.7)) + in.seed * 80);
        // A streak with round ends.
        float2 q = float2(max(0.0, abs(in.at.x) - in.stretch), in.at.y * (1 + 0.6 * abs(in.at.x) / (in.stretch + 1) * in.stretch / (in.stretch + 1.5)));
        float rag = 0.8 + 0.35 * noise(in.at * 1.7 + in.seed * 100);
        float d = length(q) / rag;
        float body = exp(-d * d * d * 1.9);
        float halo = exp(-d * d * 0.85) * 0.1;
        // Not white-hot once the page behind can be white.
        float light = min(in.heat * 1.15, mix(0.62, 2.0, now.ground)) * flicker;
        float3 c = glow(light) * body * 1.7 + float3(0.02, 0.16, 0.9) * halo * light;
        return float4(c * in.dim, saturate(body) * smoothstep(0.0, 0.12, in.heat) * in.dim);
    }

    // MARK: Drawing

    struct Screen {
        float4 position [[position]];
        float2 uv;
    };

    vertex Screen wholeScreen(uint id [[vertex_id]]) {
        float2 c = float2((id << 1) & 2, id & 2);
        Screen o;
        o.position = float4(c * 2 - 1, 0, 1);
        o.uv = float2(c.x, 1 - c.y);
        return o;
    }

    /// Smoother than the grid it's read from.
    float2 read(texture2d<float> t, float2 uv) {
        float2 size = float2(t.get_width(), t.get_height());
        float2 p = uv * size - 0.5, i = floor(p), f = p - i;
        float2 w0 = (1 - f) * (1 - f) * (1 - f) / 6, w1 = (4 - 6 * f * f + 3 * f * f * f) / 6;
        float2 w3 = f * f * f / 6, w2 = 1 - w0 - w1 - w3;
        float2 g0 = w0 + w1, g1 = w2 + w3;
        float2 a = (i - 0.5 + w1 / g0) / size, b = (i + 1.5 + w3 / g1) / size;
        return t.sample(bare, float2(a.x, a.y)).xy * g0.x * g0.y + t.sample(bare, float2(b.x, a.y)).xy * g1.x * g0.y
             + t.sample(bare, float2(a.x, b.y)).xy * g0.x * g1.y + t.sample(bare, float2(b.x, b.y)).xy * g1.x * g1.y;
    }

    fragment float4 flames(Screen in [[stage_in]], texture2d<float> fire [[texture(0)]], texture2d<float> logo [[texture(1)]],
                           constant Now &now [[buffer(0)]]) {
        float2 p = in.uv * now.size;
        float2 here = read(fire, in.uv);
        // Nothing here or close by.
        float2 off = abs(p - now.middle) - now.logo.zw * 0.5 - 12;
        float2 near = 10 / now.size;
        float warm = here.x + here.y * 0.2;
        warm += fire.sample(bare, in.uv + near).x + fire.sample(bare, in.uv - near).x
              + fire.sample(bare, in.uv + float2(near.x, -near.y)).x + fire.sample(bare, in.uv + float2(-near.x, near.y)).x;
        if (max(off.x, off.y) > 0 && warm < 0.002) return float4(0);
        // Hot air bends what's seen through it.
        float2 e = float2(now.cell * 2, 0);
        float2 slope = float2(read(fire, (p + e.xy) / now.size).y - read(fire, (p - e.xy) / now.size).y,
                              read(fire, (p + e.yx) / now.size).y - read(fire, (p - e.yx) / now.size).y);
        float2 ripple = wave(float2(p.x * 0.04, p.y * 0.05 + now.time * 5)) * 0.8
                      + wave(float2(p.x * 0.11, p.y * 0.12 + now.time * 11)) * 0.45;
        float2 bent = p + min(here.y, 1.1) * ripple * 4.5 - slope * 5;

        // The letters: white-hot as they appear, cooling to their glow; white-hot again as the bush fire reaches them,
        // then burning through.
        float2 at = (bent - now.logo.xy) / now.logo.zw;
        // Undoes what `finish` does to it, so it's just as it's drawn.
        float3 c = -log(1 - min(logo.sample(bare, at).rgb, 0.985)) / 1.25;
        float born = now.time - forms(bent, now);
        c *= smoothstep(0.0, 0.05, born);
        c += c * 4 * smoothstep(0.45, 0.0, born);
        float left = burnsAt(bent, now) - now.time;
        c *= smoothstep(-0.02, 0.015, left);
        c += c * 3 * smoothstep(0.08, 0.0, left);

        // Three sheets of flame, one behind another, each with its own fine detail.
        for (int i = 0; i < 3; i++) {
            float2 own = float2(i * 37.1, i * 91.7);
            float2 curls = wave(float2(p.x * 0.07, p.y * 0.045 + now.time * (7 + i)) + own) * (3.0 + 2.5 * i);
            float t = read(fire, (p + curls + float2((i - 1) * 2.5, i * 2.0)) / now.size).x;
            float licks = clouds(float2(p.x * 0.085, p.y * 0.028 + now.time * (7 + i)) + own);
            t = max(0.0, t - 0.5 * max(0.0, licks - 0.15) * smoothstep(1.2, 0.3, t));
            float edge = smoothstep(0.01, 0.16, t) * (1 - smoothstep(0.16, 0.5, t));
            float heart = smoothstep(0.35, 1.1, t);
            c += float3(0.03, 0.1, 0.7) * edge * (0.1 + 0.75 * licks) + float3(0.01, 0.2, 0.95) * t * sqrt(t) * 0.46
               + float3(0.2, 0.62, 0.85) * heart * heart * 0.4;
        }
        return float4(c, 0);
    }

    fragment float4 finish(Screen in [[stage_in]], texture2d<float> scene [[texture(0)]], constant Now &now [[buffer(0)]]) {
        float4 s = scene.sample(smooth, in.uv, level(0));
        // Light spills around what's bright.
        float3 spill = scene.sample(smooth, in.uv, level(2)).rgb * 0.22 + scene.sample(smooth, in.uv, level(3.5)).rgb * 0.2
                     + scene.sample(smooth, in.uv, level(5)).rgb * 0.16 + scene.sample(smooth, in.uv, level(6.5)).rgb * 0.1;
        float3 c = 1 - exp(-(s.rgb + spill) * 1.25);
        c += (hash(in.position.xy) - 0.5) / 255;
        float cover = max(now.ground, saturate(max(max(c.r, c.g), max(c.b, s.a))));
        return float4(saturate(c), cover);
    }
    """
}
