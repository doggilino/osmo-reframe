#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

struct ReframeKernelParams {
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
    uint32_t sourceWidth;
    uint32_t sourceHeight;
    uint32_t destinationWidth;
    uint32_t destinationHeight;
    uint32_t renderWidth;
    uint32_t renderHeight;
    uint32_t destinationStartX;
    uint32_t destinationStartY;
    uint32_t sourceStride;
    uint32_t destinationStride;
    uint32_t sourceXOffset;
    uint32_t sourceYOffset;
    uint32_t destinationXOffset;
    uint32_t destinationYOffset;
    uint32_t sourceFlipY;
    uint32_t destinationFlipY;
    uint32_t padding;
};

static_assert(sizeof(ReframeKernelParams) == 128, "Metal parameter layout changed");

struct Pixel {
    float r;
    float g;
    float b;
    float a;
};

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            std::cerr << "usage: shader-smoke /path/to/OsmoReframe.metallib\n";
            return 2;
        }

        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            std::cerr << "Metal device unavailable\n";
            return 1;
        }

        NSError *error = nil;
        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        id<MTLLibrary> library = [device newLibraryWithURL:url error:&error];
        id<MTLFunction> function = [library newFunctionWithName:@"osmoReframeFloat"];
        id<MTLComputePipelineState> pipeline = function
            ? [device newComputePipelineStateWithFunction:function error:&error]
            : nil;
        if (!pipeline) {
            std::cerr << "Unable to load pipeline: "
                      << (error.localizedDescription.UTF8String ?: "unknown error") << "\n";
            return 1;
        }

        constexpr uint32_t sourceWidth = 1024;
        constexpr uint32_t sourceHeight = 512;
        constexpr uint32_t destinationWidth = 320;
        constexpr uint32_t destinationHeight = 180;
        constexpr uint32_t renderWidth = 160;
        constexpr uint32_t renderHeight = 90;
        constexpr uint32_t destinationStartX = 80;
        constexpr uint32_t destinationStartY = 45;
        constexpr uint32_t destinationXOffset = 16;
        constexpr uint32_t destinationYOffset = 8;
        constexpr uint32_t destinationSurfaceWidth = 192;
        constexpr uint32_t destinationSurfaceHeight = 106;
        std::vector<Pixel> source(sourceWidth * sourceHeight);
        std::vector<Pixel> destination(destinationSurfaceWidth * destinationSurfaceHeight);
        for (uint32_t y = 0; y < sourceHeight; ++y) {
            for (uint32_t x = 0; x < sourceWidth; ++x) {
                source[y * sourceWidth + x] = {
                    (static_cast<float>(x) + 0.5f) / sourceWidth,
                    (static_cast<float>(y) + 0.5f) / sourceHeight,
                    0.25f,
                    1.0f,
                };
            }
        }

        id<MTLBuffer> sourceBuffer = [device newBufferWithBytes:source.data()
                                                         length:source.size() * sizeof(Pixel)
                                                        options:MTLResourceStorageModeShared];
        id<MTLBuffer> destinationBuffer = [device newBufferWithBytes:destination.data()
                                                              length:destination.size() * sizeof(Pixel)
                                                             options:MTLResourceStorageModeShared];
        ReframeKernelParams params = {
            .pan = 0.0f,
            .tilt = 0.0f,
            .roll = 0.0f,
            .fieldOfView = 90.0f,
            .exposure = 0.0f,
            .contrast = 0.0f,
            .saturation = 0.0f,
            .temperature = 0.0f,
            .tint = 0.0f,
            .highlights = 0.0f,
            .shadows = 0.0f,
            .projection = 0.0f,
            .inputFormat = 0.0f,
            .lensFieldOfView = 191.9f,
            .seamBlend = 0.04f,
            .sourceWidth = sourceWidth,
            .sourceHeight = sourceHeight,
            .destinationWidth = destinationWidth,
            .destinationHeight = destinationHeight,
            .renderWidth = renderWidth,
            .renderHeight = renderHeight,
            .destinationStartX = destinationStartX,
            .destinationStartY = destinationStartY,
            .sourceStride = sourceWidth,
            .destinationStride = destinationSurfaceWidth,
            .sourceXOffset = 0,
            .sourceYOffset = 0,
            .destinationXOffset = destinationXOffset,
            .destinationYOffset = destinationYOffset,
            .sourceFlipY = 0,
            .destinationFlipY = 0,
            .padding = 0,
        };

        id<MTLCommandQueue> queue = [device newCommandQueue];
        id<MTLCommandBuffer> command = [queue commandBuffer];
        id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
        [encoder setComputePipelineState:pipeline];
        [encoder setBuffer:sourceBuffer offset:0 atIndex:0];
        [encoder setBuffer:destinationBuffer offset:0 atIndex:1];
        [encoder setBytes:&params length:sizeof(params) atIndex:2];
        const NSUInteger threadWidth = pipeline.threadExecutionWidth;
        const NSUInteger threadHeight = pipeline.maxTotalThreadsPerThreadgroup / threadWidth;
        [encoder dispatchThreads:MTLSizeMake(renderWidth, renderHeight, 1)
           threadsPerThreadgroup:MTLSizeMake(threadWidth, threadHeight, 1)];
        [encoder endEncoding];
        [command commit];
        [command waitUntilCompleted];
        if (command.status == MTLCommandBufferStatusError) {
            std::cerr << "Metal command failed: " << command.error.localizedDescription.UTF8String << "\n";
            return 1;
        }

        const Pixel *result = static_cast<const Pixel *>(destinationBuffer.contents);
        const uint32_t centerRow = destinationYOffset + renderHeight / 2;
        const Pixel center = result[centerRow * destinationSurfaceWidth +
                                    destinationXOffset + renderWidth / 2];
        const Pixel left = result[centerRow * destinationSurfaceWidth +
                                  destinationXOffset + renderWidth / 4];
        const Pixel right = result[centerRow * destinationSurfaceWidth +
                                   destinationXOffset + 3 * renderWidth / 4];

        const bool centerMatches = std::abs(center.r - 0.5f) < 0.02f &&
                                   std::abs(center.g - 0.5f) < 0.02f &&
                                   std::abs(center.b - 0.25f) < 0.01f;
        const bool horizontalDirection = left.r < center.r && center.r < right.r;
        if (!centerMatches || !horizontalDirection) {
            std::cerr << "Unexpected projection result: center="
                      << center.r << "," << center.g << "," << center.b
                      << " left.r=" << left.r << " right.r=" << right.r << "\n";
            return 1;
        }

        std::cout << "Shader smoke test passed: center="
                  << center.r << "," << center.g << "," << center.b << "\n";
        return 0;
    }
}
