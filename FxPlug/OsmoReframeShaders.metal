#include <metal_stdlib>
using namespace metal;

struct ReframeParams {
    float pan;
    float tilt;
    float roll;
    float fieldOfView;
    float exposure;
    float contrast;
    float saturation;
    float temperature;
    float tint;
    float highlights;
    float shadows;
    float projection;
    float inputFormat;
    float lensFieldOfView;
    float seamBlend;
    uint sourceWidth;
    uint sourceHeight;
    uint destinationWidth;
    uint destinationHeight;
    uint renderWidth;
    uint renderHeight;
    uint destinationStartX;
    uint destinationStartY;
    uint sourceStride;
    uint destinationStride;
    uint sourceXOffset;
    uint sourceYOffset;
    uint destinationXOffset;
    uint destinationYOffset;
    uint sourceFlipY;
    uint destinationFlipY;
    uint _padding;
};

inline float3 rotateX(float3 p, float a) {
    float s = sin(a), c = cos(a);
    return float3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

inline float3 rotateY(float3 p, float a) {
    float s = sin(a), c = cos(a);
    return float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

inline float3 rotateZ(float3 p, float a) {
    float s = sin(a), c = cos(a);
    return float3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

inline float3 cameraRay(float2 uv, constant ReframeParams &p, thread bool &inside) {
    constexpr float pi = M_PI_F;
    const float aspect = float(p.destinationWidth) / max(float(p.destinationHeight), 1.0f);
    float2 q = float2((uv.x * 2.0f - 1.0f) * aspect, 1.0f - uv.y * 2.0f);
    float fov = clamp(p.fieldOfView, 1.0f, 359.0f) * pi / 180.0f;
    float3 ray;
    inside = true;

    if (p.projection < 0.5f) {
        float scale = tan(min(fov, pi - 0.001f) * 0.5f);
        ray = normalize(float3(q * scale, 1.0f));
    } else if (p.projection < 1.5f) {
        float radius = length(q);
        if (radius > 1.0f) {
            inside = false;
            return float3(0.0f, 0.0f, 1.0f);
        }
        float theta = radius * min(fov, 2.0f * pi) * 0.5f;
        float2 radial = radius > 1e-6f ? q / radius : float2(0.0f);
        ray = float3(radial * sin(theta), cos(theta));
    } else {
        float zoom = tan(clamp(fov, 20.0f * pi / 180.0f, 340.0f * pi / 180.0f) * 0.25f);
        float2 plane = q * max(zoom, 0.01f);
        float r2 = dot(plane, plane);
        // Inverse stereographic projection centered on the nadir.
        ray = normalize(float3(2.0f * plane.x, r2 - 1.0f, 2.0f * plane.y));
    }

    ray = rotateZ(ray, p.roll);
    ray = rotateX(ray, p.tilt);
    ray = rotateY(ray, p.pan);
    return ray;
}

inline float3 grade(float3 color, constant ReframeParams &p) {
    color *= exp2(p.exposure);

    float warmth = p.temperature * 0.01f;
    float greenShift = p.tint * 0.01f;
    color *= float3(exp2(warmth), exp2(greenShift * 0.5f), exp2(-warmth));

    float luminance = dot(color, float3(0.2126f, 0.7152f, 0.0722f));
    color = mix(float3(luminance), color, max(0.0f, 1.0f + p.saturation));
    color = (color - 0.18f) * max(0.0f, 1.0f + p.contrast) + 0.18f;

    float shadowMask = 1.0f - smoothstep(0.0f, 0.45f, luminance);
    float highlightMask = smoothstep(0.35f, 1.0f, luminance);
    color *= exp2(p.shadows * shadowMask + p.highlights * highlightMask);
    return max(color, float3(0.0f));
}

template <typename Pixel>
inline Pixel fetchPixel(device const Pixel *source,
                        int x,
                        int y,
                        constant ReframeParams &p,
                        bool wrapX) {
    int sampleX = x;
    if (wrapX) {
        sampleX %= int(p.sourceWidth);
        if (sampleX < 0) sampleX += int(p.sourceWidth);
    } else {
        sampleX = clamp(sampleX, 0, int(p.sourceWidth) - 1);
    }
    int clampedY = clamp(y, 0, int(p.sourceHeight) - 1);
    uint physicalY = p.sourceFlipY != 0
        ? p.sourceYOffset + (p.sourceHeight - 1u - uint(clampedY))
        : p.sourceYOffset + uint(clampedY);
    return source[physicalY * p.sourceStride + p.sourceXOffset + uint(sampleX)];
}

template <typename Pixel>
inline float4 sampleBilinear(device const Pixel *source,
                             float2 uv,
                             constant ReframeParams &p,
                             bool wrapX) {
    float x = uv.x * float(p.sourceWidth) - 0.5f;
    float y = uv.y * float(p.sourceHeight) - 0.5f;
    int x0 = int(floor(x));
    int y0 = int(floor(y));
    float2 f = fract(float2(x, y));
    float4 a = float4(fetchPixel(source, x0, y0, p, wrapX));
    float4 b = float4(fetchPixel(source, x0 + 1, y0, p, wrapX));
    float4 c = float4(fetchPixel(source, x0, y0 + 1, p, wrapX));
    float4 d = float4(fetchPixel(source, x0 + 1, y0 + 1, p, wrapX));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

inline float2 fisheyeCoordinate(float3 direction,
                                bool rightLens,
                                constant ReframeParams &p,
                                thread bool &valid) {
    float3 lensDirection = direction;
    if (rightLens) {
        lensDirection.x = -lensDirection.x;
        lensDirection.z = -lensDirection.z;
    }

    float theta = acos(clamp(lensDirection.z, -1.0f, 1.0f));
    float phi = atan2(lensDirection.y, lensDirection.x);
    float lensFov = clamp(p.lensFieldOfView, 180.0f, 240.0f) * M_PI_F / 180.0f;
    float radius = theta / (lensFov * 0.5f);
    valid = radius <= 1.0f;
    float2 position = float2(cos(phi), sin(phi)) * radius;
    return rightLens
        ? float2(0.75f + position.x * 0.25f, 0.5f + position.y * 0.5f)
        : float2(0.25f + position.x * 0.25f, 0.5f + position.y * 0.5f);
}

template <typename Pixel>
inline float4 sampleDualFisheye(device const Pixel *source,
                                float3 direction,
                                constant ReframeParams &p) {
    bool validLeft;
    bool validRight;
    float2 leftUV = fisheyeCoordinate(direction, false, p, validLeft);
    float2 rightUV = fisheyeCoordinate(direction, true, p, validRight);

    if (validLeft && validRight) {
        float width = max(p.seamBlend, 0.00001f);
        float blend = smoothstep(-width, width, direction.z);
        float4 left = sampleBilinear(source, leftUV, p, false);
        float4 right = sampleBilinear(source, rightUV, p, false);
        return mix(right, left, blend);
    }
    if (validLeft) return sampleBilinear(source, leftUV, p, false);
    if (validRight) return sampleBilinear(source, rightUV, p, false);
    return float4(0.0f, 0.0f, 0.0f, 1.0f);
}

template <typename Pixel>
inline void reframe(device const Pixel *source,
                    device Pixel *destination,
                    constant ReframeParams &p,
                    uint2 gid) {
    if (gid.x >= p.renderWidth || gid.y >= p.renderHeight) return;

    float2 imagePosition = float2(p.destinationStartX + gid.x,
                                  p.destinationStartY + gid.y);
    float2 uv = (imagePosition + 0.5f) / float2(p.destinationWidth, p.destinationHeight);
    bool inside;
    float3 direction = cameraRay(uv, p, inside);
    float4 output = float4(0.0f, 0.0f, 0.0f, 1.0f);
    if (inside) {
        constexpr float pi = M_PI_F;
        if (p.inputFormat < 0.5f) {
            float longitude = atan2(direction.x, direction.z);
            float latitude = asin(clamp(direction.y, -1.0f, 1.0f));
            float2 sourceUV = float2(longitude / (2.0f * pi) + 0.5f,
                                     0.5f - latitude / pi);
            output = sampleBilinear(source, sourceUV, p, true);
        } else {
            output = sampleDualFisheye(source, direction, p);
        }
        output.rgb = grade(output.rgb, p);
    }

    uint physicalY = p.destinationFlipY != 0
        ? p.destinationYOffset + (p.renderHeight - 1u - gid.y)
        : p.destinationYOffset + gid.y;
    destination[physicalY * p.destinationStride + p.destinationXOffset + gid.x] = Pixel(output);
}

kernel void osmoReframeHalf(device const half4 *source [[buffer(0)]],
                            device half4 *destination [[buffer(1)]],
                            constant ReframeParams &params [[buffer(2)]],
                            uint2 gid [[thread_position_in_grid]]) {
    reframe(source, destination, params, gid);
}

kernel void osmoReframeFloat(device const float4 *source [[buffer(0)]],
                             device float4 *destination [[buffer(1)]],
                             constant ReframeParams &params [[buffer(2)]],
                             uint2 gid [[thread_position_in_grid]]) {
    reframe(source, destination, params, gid);
}
