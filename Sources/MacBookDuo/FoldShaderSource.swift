enum FoldShaderSource {
    // Custom reconstruction, not Apple's proprietary Duo shader.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct FoldUniforms {
        float progress, aspect, maxTilt, blurStrength, darkening, voidStrength, effectBlend;
    };
    struct Vertex { float2 position; float2 uv; };
    struct VertexOut { float4 position [[position]]; float2 uv; };

    vertex VertexOut fold_vertex(uint id [[vertex_id]],
                                 constant Vertex *vertices [[buffer(0)]]) {
        // Rasterize the entire physical display. Geometry lives in the pixel shader.
        VertexOut out;
        out.position = float4(vertices[id].position, 0.0, 1.0);
        out.uv = vertices[id].uv;
        return out;
    }
    constexpr sampler imageSampler(filter::linear, address::clamp_to_zero);

    fragment float4 fold_fragment(VertexOut in [[stage_in]],
        texture2d<float> source [[texture(0)]],
        constant FoldUniforms &u [[buffer(1)]]) {
        float p = clamp(u.progress, 0.0, 1.0);
        float3 original = source.sample(imageSampler, in.uv).rgb;
        if (p == 0.0 || u.effectBlend <= 0.0) return float4(original, 1.0);
        // Display height = 1, hinge at y=0,z=0, stationary content at z=0.
        // +z is toward the viewer. Closing moves the upper edge toward them.
        float aspect = max(u.aspect, 0.1);
        float h = 1.0 - in.uv.y;
        float angle = p * u.maxTilt;
        float3 eye = float3(0.0, 0.5, 2.5);
        float3 glass = float3((in.uv.x - 0.5) * aspect,
                              h * cos(angle), h * sin(angle));
        // Intersect eye + t*(glass-eye) with z=0. eye.z > 1 prevents singularities.
        float t = eye.z / (eye.z - glass.z);
        float3 hit = eye + t * (glass - eye);
        float2 uv = float2(hit.x / aspect + 0.5, 1.0 - hit.y);
        // Gap controls shading only. Reference footage shows a distinct sharp
        // lower region, not a nearly uniform blur proportional to optical gap.
        float gap = length(hit - glass);
        // Empirical reconstruction, not a measured curve from the reference.
        // Use physical rotation so manual and sensor modes share the same blur.
        float fold = clamp(angle / (M_PI_F * 0.5), 0.0, 1.0);
        float spread = smoothstep(0.03, 0.85, fold);
        // h=0 is the hinge. The clear region shrinks as the display closes;
        // a broad smooth transition avoids a visible horizontal wipe boundary.
        float clearHeight = mix(0.82, 0.06, spread);
        float transitionWidth = mix(0.24, 0.48, spread);
        float localDefocus = smoothstep(clearHeight,
                                       clearHeight + transitionWidth, h);
        float peakRadius = 0.085 * smoothstep(0.02, 0.72, fold);
        float radius = peakRadius * localDefocus * u.blurStrength;
        float3 color = float3(0.0);
        float totalWeight = 0.0;
        constexpr int count = 48;
        for (int i = 0; i < count; ++i) {
            float r2 = (float(i) + 0.5) / float(count);
            float phi = float(i) * 2.39996323;
            float2 offset = float2(cos(phi) / aspect, sin(phi)) * sqrt(r2) * radius;
            float weight = exp(-2.0 * r2);
            // Outside the finite content plane is black; never stretch its edges.
            color += source.sample(imageSampler, uv + offset).rgb * weight;
            totalWeight += weight;
        }
        color /= totalWeight;
        color *= exp(-u.darkening * gap);
        color *= 1.0 - u.voidStrength * smoothstep(0.94, 1.0, p);
        float blend = smoothstep(0.0, 1.0, clamp(u.effectBlend, 0.0, 1.0));
        return float4(mix(original, color, blend), 1.0);
    }
    """
}
