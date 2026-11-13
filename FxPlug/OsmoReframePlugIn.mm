#import "OsmoReframePlugIn.h"

#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <cstdint>

namespace {

enum ParameterID : UInt32 {
    kViewGroupID = 100,
    kProjectionID = 101,
    kPanID = 102,
    kTiltID = 103,
    kRollID = 104,
    kFieldOfViewID = 105,
    kInputFormatID = 106,
    kLensFieldOfViewID = 107,
    kSeamBlendID = 108,
    kColorGroupID = 200,
    kExposureID = 201,
    kContrastID = 202,
    kSaturationID = 203,
    kTemperatureID = 204,
    kTintID = 205,
    kHighlightsID = 206,
    kShadowsID = 207,
};

struct ReframeState {
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
};

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

static_assert(sizeof(ReframeKernelParams) == 128, "Metal parameter layout must remain stable");

NSError *pluginError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:FxPlugErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

uint32_t rectWidth(FxRect rect) {
    return static_cast<uint32_t>(std::max<SInt32>(rect.right - rect.left, 0));
}

uint32_t rectHeight(FxRect rect) {
    return static_cast<uint32_t>(std::max<SInt32>(rect.top - rect.bottom, 0));
}

} // namespace

@implementation OsmoReframePlugIn {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLComputePipelineState> _halfPipeline;
    id<MTLComputePipelineState> _floatPipeline;
    NSError *_metalError;
}

- (nullable instancetype)initWithAPIManager:(id<PROAPIAccessing>)apiManager {
    self = [super init];
    if (!self) return nil;

    _apiManager = apiManager;
    _device = MTLCreateSystemDefaultDevice();
    _commandQueue = [_device newCommandQueue];
    if (!_device || !_commandQueue) {
        _metalError = pluginError(kFxError_APIUnavailable, @"Metal is unavailable");
        return self;
    }

    NSError *libraryError = nil;
    NSURL *libraryURL = [[NSBundle bundleForClass:self.class] URLForResource:@"OsmoReframe"
                                                              withExtension:@"metallib"];
    id<MTLLibrary> library = libraryURL ? [_device newLibraryWithURL:libraryURL error:&libraryError] : nil;
    if (!library) {
        _metalError = libraryError ?: pluginError(kFxError_APIUnavailable,
                                                   @"OsmoReframe Metal library is unavailable");
        return self;
    }

    id<MTLFunction> halfFunction = [library newFunctionWithName:@"osmoReframeHalf"];
    id<MTLFunction> floatFunction = [library newFunctionWithName:@"osmoReframeFloat"];
    NSError *pipelineError = nil;
    if (halfFunction) {
        _halfPipeline = [_device newComputePipelineStateWithFunction:halfFunction error:&pipelineError];
    }
    if (!_halfPipeline) {
        _metalError = pipelineError ?: pluginError(kFxError_APIUnavailable,
                                                    @"Unable to create the half-float reframe pipeline");
        return self;
    }
    if (floatFunction) {
        _floatPipeline = [_device newComputePipelineStateWithFunction:floatFunction error:&pipelineError];
    }
    if (!_floatPipeline) {
        _metalError = pipelineError ?: pluginError(kFxError_APIUnavailable,
                                                    @"Unable to create the float reframe pipeline");
    }
    return self;
}

- (BOOL)properties:(NSDictionary * _Nonnull *)properties error:(NSError **)error {
    *properties = @{
        kFxPropertyKey_MayRemapTime: @NO,
        kFxPropertyKey_NeedsFullBuffer: @YES,
        kFxPropertyKey_VariesWhenParamsAreStatic: @NO,
        kFxPropertyKey_ChangesOutputSize: @NO,
        kFxPropertyKey_PixelTransformSupport: @(kFxPixelTransform_ScaleTranslate),
        kFxPropertyKey_DesiredProcessingColorInfo: @(kFxImageColorInfo_RGB_LINEAR),
    };
    return YES;
}

- (BOOL)addParametersWithError:(NSError **)error {
    id<FxParameterCreationAPI_v5> api = [_apiManager apiForProtocol:@protocol(FxParameterCreationAPI_v5)];
    if (!api) {
        if (error) *error = pluginError(kFxError_APIUnavailable,
                                        @"FxPlug parameter creation API is unavailable");
        return NO;
    }

    const FxParameterFlags groupFlags = kFxParameterFlag_COLLAPSED |
                                         kFxParameterFlag_DONT_DISPLAY_IN_DASHBOARD;
    const FxParameterFlags controlFlags = kFxParameterFlag_DEFAULT;
    BOOL added =
        [api startParameterSubGroup:@"View"
                       parameterID:kViewGroupID
                    parameterFlags:kFxParameterFlag_DEFAULT] &&
        [api addPopupMenuWithName:@"Input Format"
                      parameterID:kInputFormatID
                     defaultValue:0
                      menuEntries:@[@"Equirectangular", @"Osmo Dual Fisheye"]
                   parameterFlags:kFxParameterFlag_NOT_ANIMATABLE] &&
        [api addPopupMenuWithName:@"Projection"
                      parameterID:kProjectionID
                     defaultValue:0
                      menuEntries:@[@"Rectilinear", @"Fisheye", @"Tiny Planet"]
                   parameterFlags:controlFlags] &&
        [api addAngleSliderWithName:@"Pan"
                        parameterID:kPanID
                     defaultDegrees:0.0
                parameterMinDegrees:-720.0
                parameterMaxDegrees:720.0
                     parameterFlags:controlFlags] &&
        [api addAngleSliderWithName:@"Tilt"
                        parameterID:kTiltID
                     defaultDegrees:0.0
                parameterMinDegrees:-180.0
                parameterMaxDegrees:180.0
                     parameterFlags:controlFlags] &&
        [api addAngleSliderWithName:@"Roll"
                        parameterID:kRollID
                     defaultDegrees:0.0
                parameterMinDegrees:-180.0
                parameterMaxDegrees:180.0
                     parameterFlags:controlFlags] &&
        [api addFloatSliderWithName:@"Field of View"
                        parameterID:kFieldOfViewID
                       defaultValue:90.0
                       parameterMin:1.0
                       parameterMax:359.0
                          sliderMin:20.0
                          sliderMax:180.0
                              delta:0.1
                     parameterFlags:controlFlags] &&
        [api addFloatSliderWithName:@"Lens FOV"
                        parameterID:kLensFieldOfViewID
                       defaultValue:191.9
                       parameterMin:180.0
                       parameterMax:240.0
                          sliderMin:185.0
                          sliderMax:210.0
                              delta:0.1
                     parameterFlags:controlFlags] &&
        [api addFloatSliderWithName:@"Seam Blend"
                        parameterID:kSeamBlendID
                       defaultValue:0.04
                       parameterMin:0.0
                       parameterMax:0.25
                          sliderMin:0.0
                          sliderMax:0.12
                              delta:0.001
                     parameterFlags:controlFlags] &&
        [api endParameterSubGroup] &&
        [api startParameterSubGroup:@"Color"
                       parameterID:kColorGroupID
                    parameterFlags:groupFlags] &&
        [api addFloatSliderWithName:@"Exposure"
                        parameterID:kExposureID
                       defaultValue:0.0
                       parameterMin:-8.0
                       parameterMax:8.0
                          sliderMin:-3.0
                          sliderMax:3.0
                              delta:0.05
                     parameterFlags:controlFlags] &&
        [api addFloatSliderWithName:@"Contrast"
                        parameterID:kContrastID
                       defaultValue:0.0
                       parameterMin:-1.0
                       parameterMax:2.0
                          sliderMin:-1.0
                          sliderMax:1.0
                              delta:0.01
                     parameterFlags:controlFlags] &&
        [api addFloatSliderWithName:@"Saturation"
                        parameterID:kSaturationID
                       defaultValue:0.0
                       parameterMin:-1.0
                       parameterMax:2.0
                          sliderMin:-1.0
                          sliderMax:1.0
                              delta:0.01
                     parameterFlags:controlFlags] &&
        [api addFloatSliderWithName:@"Temperature"
                        parameterID:kTemperatureID
                       defaultValue:0.0
                       parameterMin:-100.0
                       parameterMax:100.0
                          sliderMin:-25.0
                          sliderMax:25.0
                              delta:0.25
                     parameterFlags:controlFlags] &&
        [api addFloatSliderWithName:@"Tint"
                        parameterID:kTintID
                       defaultValue:0.0
                       parameterMin:-100.0
                       parameterMax:100.0
                          sliderMin:-25.0
                          sliderMax:25.0
                              delta:0.25
                     parameterFlags:controlFlags] &&
        [api addFloatSliderWithName:@"Highlights"
                        parameterID:kHighlightsID
                       defaultValue:0.0
                       parameterMin:-2.0
                       parameterMax:2.0
                          sliderMin:-1.0
                          sliderMax:1.0
                              delta:0.01
                     parameterFlags:controlFlags] &&
        [api addFloatSliderWithName:@"Shadows"
                        parameterID:kShadowsID
                       defaultValue:0.0
                       parameterMin:-2.0
                       parameterMax:2.0
                          sliderMin:-1.0
                          sliderMax:1.0
                              delta:0.01
                     parameterFlags:controlFlags] &&
        [api endParameterSubGroup];

    if (!added && error) {
        *error = pluginError(kFxError_InvalidParameter,
                             @"Unable to create the OsmoReframe inspector controls");
    }
    return added;
}

- (BOOL)pluginState:(NSData **)pluginState
             atTime:(CMTime)renderTime
            quality:(FxQuality)qualityLevel
              error:(NSError **)error {
    id<FxParameterRetrievalAPI_v6> api = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (!api) {
        if (error) *error = pluginError(kFxError_APIUnavailable,
                                        @"FxPlug parameter retrieval API is unavailable");
        return NO;
    }

    int projection = 0, inputFormat = 0;
    double pan = 0.0, tilt = 0.0, roll = 0.0, fieldOfView = 90.0;
    double lensFieldOfView = 191.9, seamBlend = 0.04;
    double exposure = 0.0, contrast = 0.0, saturation = 0.0;
    double temperature = 0.0, tint = 0.0, highlights = 0.0, shadows = 0.0;
    [api getIntValue:&projection fromParameter:kProjectionID atTime:renderTime];
    [api getIntValue:&inputFormat fromParameter:kInputFormatID atTime:renderTime];
    [api getFloatValue:&pan fromParameter:kPanID atTime:renderTime];
    [api getFloatValue:&tilt fromParameter:kTiltID atTime:renderTime];
    [api getFloatValue:&roll fromParameter:kRollID atTime:renderTime];
    [api getFloatValue:&fieldOfView fromParameter:kFieldOfViewID atTime:renderTime];
    [api getFloatValue:&lensFieldOfView fromParameter:kLensFieldOfViewID atTime:renderTime];
    [api getFloatValue:&seamBlend fromParameter:kSeamBlendID atTime:renderTime];
    [api getFloatValue:&exposure fromParameter:kExposureID atTime:renderTime];
    [api getFloatValue:&contrast fromParameter:kContrastID atTime:renderTime];
    [api getFloatValue:&saturation fromParameter:kSaturationID atTime:renderTime];
    [api getFloatValue:&temperature fromParameter:kTemperatureID atTime:renderTime];
    [api getFloatValue:&tint fromParameter:kTintID atTime:renderTime];
    [api getFloatValue:&highlights fromParameter:kHighlightsID atTime:renderTime];
    [api getFloatValue:&shadows fromParameter:kShadowsID atTime:renderTime];

    ReframeState state = {
        .pan = static_cast<float>(pan),
        .tilt = static_cast<float>(tilt),
        .roll = static_cast<float>(roll),
        .fieldOfView = static_cast<float>(fieldOfView),
        .exposure = static_cast<float>(exposure),
        .contrast = static_cast<float>(contrast),
        .saturation = static_cast<float>(saturation),
        .temperature = static_cast<float>(temperature),
        .tint = static_cast<float>(tint),
        .highlights = static_cast<float>(highlights),
        .shadows = static_cast<float>(shadows),
        .projection = static_cast<float>(std::clamp(projection, 0, 2)),
        .inputFormat = static_cast<float>(std::clamp(inputFormat, 0, 1)),
        .lensFieldOfView = static_cast<float>(std::clamp(lensFieldOfView, 180.0, 240.0)),
        .seamBlend = static_cast<float>(std::clamp(seamBlend, 0.0, 0.25)),
    };
    *pluginState = [NSData dataWithBytes:&state length:sizeof(state)];
    return *pluginState != nil;
}

- (BOOL)destinationImageRect:(FxRect *)destinationImageRect
                sourceImages:(NSArray<FxImageTile *> *)sourceImages
            destinationImage:(FxImageTile *)destinationImage
                 pluginState:(NSData *)pluginState
                      atTime:(CMTime)renderTime
                       error:(NSError **)error {
    if (sourceImages.count < 1) return NO;
    *destinationImageRect = sourceImages[0].imagePixelBounds;
    return YES;
}

- (BOOL)sourceTileRect:(FxRect *)sourceTileRect
      sourceImageIndex:(NSUInteger)sourceImageIndex
          sourceImages:(NSArray<FxImageTile *> *)sourceImages
   destinationTileRect:(FxRect)destinationTileRect
      destinationImage:(FxImageTile *)destinationImage
           pluginState:(NSData *)pluginState
                atTime:(CMTime)renderTime
                 error:(NSError **)error {
    if (sourceImages.count < 1) return NO;
    *sourceTileRect = sourceImages[0].imagePixelBounds;
    return YES;
}

- (BOOL)renderDestinationImage:(FxImageTile *)destinationImage
                  sourceImages:(NSArray<FxImageTile *> *)sourceImages
                   pluginState:(NSData *)pluginState
                        atTime:(CMTime)renderTime
                         error:(NSError **)error {
    if (_metalError || !_halfPipeline || !_floatPipeline || sourceImages.count < 1 ||
        pluginState.length < sizeof(ReframeState)) {
        if (error) *error = _metalError ?: pluginError(kFxError_InvalidParameter,
                                                       @"OsmoReframe renderer is unavailable");
        return NO;
    }

    IOSurfaceRef sourceSurface = (__bridge IOSurfaceRef)sourceImages[0].ioSurface;
    IOSurfaceRef destinationSurface = (__bridge IOSurfaceRef)destinationImage.ioSurface;
    if (!sourceSurface || !destinationSurface) {
        if (error) *error = pluginError(kFxError_InvalidParameter,
                                        @"Final Cut did not provide IOSurface image buffers");
        return NO;
    }

    const size_t sourceBytesPerElement = IOSurfaceGetBytesPerElement(sourceSurface);
    const size_t destinationBytesPerElement = IOSurfaceGetBytesPerElement(destinationSurface);
    if (sourceBytesPerElement != destinationBytesPerElement ||
        (sourceBytesPerElement != 8 && sourceBytesPerElement != 16)) {
        if (error) *error = pluginError(kFxError_InvalidParameter,
                                        @"OsmoReframe requires RGBA16F or RGBA32F buffers");
        return NO;
    }

    const FxRect sourceImageBounds = sourceImages[0].imagePixelBounds;
    const FxRect sourceTileBounds = sourceImages[0].tilePixelBounds;
    const FxRect destinationImageBounds = destinationImage.imagePixelBounds;
    const FxRect destinationTileBounds = destinationImage.tilePixelBounds;
    const uint32_t sourceWidth = rectWidth(sourceImageBounds);
    const uint32_t sourceHeight = rectHeight(sourceImageBounds);
    const uint32_t destinationWidth = rectWidth(destinationImageBounds);
    const uint32_t destinationHeight = rectHeight(destinationImageBounds);
    if (sourceWidth == 0 || sourceHeight == 0 || destinationWidth == 0 || destinationHeight == 0) {
        if (error) *error = pluginError(kFxError_InvalidParameter, @"Invalid render dimensions");
        return NO;
    }

    // Final Cut can provide a padded or scaled destination tile even when the effect asks for the
    // full source buffer. Dispatch only the common image region, while retaining full-image pixel
    // coordinates for the spherical projection. Treating the IOSurface as a full 4K frame is safe
    // in a standalone test but writes outside Final Cut's render tile and produces a black viewer.
    const SInt32 renderLeft = std::max({sourceTileBounds.left, sourceImageBounds.left,
                                       destinationTileBounds.left, destinationImageBounds.left});
    const SInt32 renderBottom = std::max({sourceTileBounds.bottom, sourceImageBounds.bottom,
                                         destinationTileBounds.bottom, destinationImageBounds.bottom});
    const SInt32 renderRight = std::min({sourceTileBounds.right, sourceImageBounds.right,
                                        destinationTileBounds.right, destinationImageBounds.right});
    const SInt32 renderTop = std::min({sourceTileBounds.top, sourceImageBounds.top,
                                      destinationTileBounds.top, destinationImageBounds.top});
    const int32_t renderWidth = renderRight - renderLeft;
    const int32_t renderHeight = renderTop - renderBottom;
    if (renderWidth <= 0 || renderHeight <= 0) {
        if (error) *error = pluginError(kFxError_InvalidParameter, @"Empty Final Cut render tile");
        return NO;
    }

    if (IOSurfaceLock(sourceSurface, kIOSurfaceLockReadOnly, nullptr) != KERN_SUCCESS) {
        if (error) *error = pluginError(kFxError_InvalidParameter, @"Unable to lock the source image");
        return NO;
    }
    if (IOSurfaceLock(destinationSurface, 0, nullptr) != KERN_SUCCESS) {
        IOSurfaceUnlock(sourceSurface, kIOSurfaceLockReadOnly, nullptr);
        if (error) *error = pluginError(kFxError_InvalidParameter, @"Unable to lock the destination image");
        return NO;
    }

    void *sourceBase = IOSurfaceGetBaseAddress(sourceSurface);
    void *destinationBase = IOSurfaceGetBaseAddress(destinationSurface);
    const size_t sourceAllocation = IOSurfaceGetAllocSize(sourceSurface);
    const size_t destinationAllocation = IOSurfaceGetAllocSize(destinationSurface);
    id<MTLBuffer> sourceBuffer = [_device newBufferWithBytesNoCopy:sourceBase
                                                            length:sourceAllocation
                                                           options:MTLResourceStorageModeShared
                                                       deallocator:nil];
    id<MTLBuffer> destinationBuffer = [_device newBufferWithBytesNoCopy:destinationBase
                                                                 length:destinationAllocation
                                                                options:MTLResourceStorageModeShared
                                                            deallocator:nil];
    if (!sourceBuffer || !destinationBuffer) {
        IOSurfaceUnlock(destinationSurface, 0, nullptr);
        IOSurfaceUnlock(sourceSurface, kIOSurfaceLockReadOnly, nullptr);
        if (error) *error = pluginError(kFxError_InvalidParameter,
                                        @"Unable to expose Final Cut image memory to Metal");
        return NO;
    }

    ReframeState state;
    [pluginState getBytes:&state length:sizeof(state)];
    const BOOL sourceTopLeft = sourceImages[0].imageOrigin == kFxImageOrigin_TOP_LEFT;
    const BOOL destinationTopLeft = destinationImage.imageOrigin == kFxImageOrigin_TOP_LEFT;
    const int32_t sourceXOffsetValue = sourceImageBounds.left - sourceTileBounds.left;
    const int32_t sourceYOffsetValue = sourceTopLeft
        ? sourceTileBounds.top - sourceImageBounds.top
        : sourceImageBounds.bottom - sourceTileBounds.bottom;
    const int32_t destinationXOffsetValue = renderLeft - destinationTileBounds.left;
    const int32_t destinationYOffsetValue = destinationTopLeft
        ? destinationTileBounds.top - renderTop
        : renderBottom - destinationTileBounds.bottom;
    const size_t sourceSurfaceWidth = IOSurfaceGetWidth(sourceSurface);
    const size_t sourceSurfaceHeight = IOSurfaceGetHeight(sourceSurface);
    const size_t destinationSurfaceWidth = IOSurfaceGetWidth(destinationSurface);
    const size_t destinationSurfaceHeight = IOSurfaceGetHeight(destinationSurface);
    if (sourceXOffsetValue < 0 || sourceYOffsetValue < 0 ||
        destinationXOffsetValue < 0 || destinationYOffsetValue < 0 ||
        static_cast<size_t>(sourceXOffsetValue) + sourceWidth > sourceSurfaceWidth ||
        static_cast<size_t>(sourceYOffsetValue) + sourceHeight > sourceSurfaceHeight ||
        static_cast<size_t>(destinationXOffsetValue + renderWidth) > destinationSurfaceWidth ||
        static_cast<size_t>(destinationYOffsetValue + renderHeight) > destinationSurfaceHeight) {
        IOSurfaceUnlock(destinationSurface, 0, nullptr);
        IOSurfaceUnlock(sourceSurface, kIOSurfaceLockReadOnly, nullptr);
        if (error) *error = pluginError(kFxError_InvalidParameter,
                                        @"FxPlug tile geometry does not contain the requested image region");
        return NO;
    }

    ReframeKernelParams params = {
        .pan = state.pan,
        .tilt = state.tilt,
        .roll = state.roll,
        .fieldOfView = state.fieldOfView,
        .exposure = state.exposure,
        .contrast = state.contrast,
        .saturation = state.saturation,
        .temperature = state.temperature,
        .tint = state.tint,
        .highlights = state.highlights,
        .shadows = state.shadows,
        .projection = state.projection,
        .inputFormat = state.inputFormat,
        .lensFieldOfView = state.lensFieldOfView,
        .seamBlend = state.seamBlend,
        .sourceWidth = sourceWidth,
        .sourceHeight = sourceHeight,
        .destinationWidth = destinationWidth,
        .destinationHeight = destinationHeight,
        .renderWidth = static_cast<uint32_t>(renderWidth),
        .renderHeight = static_cast<uint32_t>(renderHeight),
        .destinationStartX = static_cast<uint32_t>(renderLeft - destinationImageBounds.left),
        .destinationStartY = static_cast<uint32_t>(destinationImageBounds.top - renderTop),
        .sourceStride = static_cast<uint32_t>(IOSurfaceGetBytesPerRow(sourceSurface) / sourceBytesPerElement),
        .destinationStride = static_cast<uint32_t>(IOSurfaceGetBytesPerRow(destinationSurface) / destinationBytesPerElement),
        .sourceXOffset = static_cast<uint32_t>(sourceXOffsetValue),
        .sourceYOffset = static_cast<uint32_t>(sourceYOffsetValue),
        .destinationXOffset = static_cast<uint32_t>(destinationXOffsetValue),
        .destinationYOffset = static_cast<uint32_t>(destinationYOffsetValue),
        .sourceFlipY = sourceTopLeft ? 0u : 1u,
        .destinationFlipY = destinationTopLeft ? 0u : 1u,
        .padding = 0u,
    };

    id<MTLComputePipelineState> pipeline = sourceBytesPerElement == 8 ? _halfPipeline : _floatPipeline;
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    [encoder setComputePipelineState:pipeline];
    [encoder setBuffer:sourceBuffer offset:0 atIndex:0];
    [encoder setBuffer:destinationBuffer offset:0 atIndex:1];
    [encoder setBytes:&params length:sizeof(params) atIndex:2];

    const NSUInteger width = pipeline.threadExecutionWidth;
    const NSUInteger height = std::max<NSUInteger>(1, pipeline.maxTotalThreadsPerThreadgroup / width);
    [encoder dispatchThreads:MTLSizeMake(renderWidth, renderHeight, 1)
       threadsPerThreadgroup:MTLSizeMake(width, height, 1)];
    [encoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    IOSurfaceUnlock(destinationSurface, 0, nullptr);
    IOSurfaceUnlock(sourceSurface, kIOSurfaceLockReadOnly, nullptr);

    if (commandBuffer.status == MTLCommandBufferStatusError) {
        if (error) *error = commandBuffer.error ?: pluginError(kFxError_ThirdPartyDeveloperStart + 1,
                                                               @"Metal render failed");
        return NO;
    }
    return YES;
}

@end
