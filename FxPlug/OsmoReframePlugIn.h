#import <Foundation/Foundation.h>
#import <FxPlug/FxPlugSDK.h>

@interface OsmoReframePlugIn : NSObject <FxTileableEffect>
@property(nonatomic, strong) id<PROAPIAccessing> apiManager;
@end

