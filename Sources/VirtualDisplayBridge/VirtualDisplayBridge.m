#import "VirtualDisplayBridge.h"
#import <objc/runtime.h>

// Undocumented system interfaces, resolved by name so missing classes do not
// prevent the physical-display controller from launching. No BetterDisplay code
// is included. See docs/architecture.md for the compatibility boundary.
@interface NSObject (CDVirtualInterfaces)
- (id)initWithDescriptor:(id)descriptor;
- (id)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
- (BOOL)applySettings:(id)settings;
- (unsigned int)displayID;
- (void)setQueue:(dispatch_queue_t)queue;
- (void)setName:(NSString *)name;
- (void)setMaxPixelsWide:(unsigned int)value;
- (void)setMaxPixelsHigh:(unsigned int)value;
- (void)setSizeInMillimeters:(CGSize)value;
- (void)setRedPrimary:(CGPoint)value;
- (void)setGreenPrimary:(CGPoint)value;
- (void)setBluePrimary:(CGPoint)value;
- (void)setWhitePoint:(CGPoint)value;
- (void)setVendorID:(unsigned int)value;
- (void)setProductID:(unsigned int)value;
- (void)setSerialNum:(unsigned int)value;
- (void)setSerialNumber:(unsigned int)value;
- (void)setHiDPI:(unsigned int)value;
- (void)setModes:(NSArray *)value;
@end

@implementation CDVirtualDisplay {
    id _display;
}

+ (BOOL)available {
    NSDictionary<NSString *, NSArray<NSString *> *> *requirements = @{
        @"CGVirtualDisplayDescriptor": @[@"setQueue:", @"setName:", @"setMaxPixelsWide:",
            @"setMaxPixelsHigh:", @"setSizeInMillimeters:", @"setRedPrimary:",
            @"setGreenPrimary:", @"setBluePrimary:", @"setWhitePoint:",
            @"setVendorID:", @"setProductID:", @"setSerialNum:"],
        @"CGVirtualDisplayMode": @[@"initWithWidth:height:refreshRate:"],
        @"CGVirtualDisplaySettings": @[@"setHiDPI:", @"setModes:"],
        @"CGVirtualDisplay": @[@"initWithDescriptor:", @"applySettings:", @"displayID"]
    };
    for (NSString *name in requirements) {
        Class cls = NSClassFromString(name);
        if (!cls) return NO;
        for (NSString *selector in requirements[name]) {
            if (![cls instancesRespondToSelector:NSSelectorFromString(selector)]) return NO;
        }
    }
    return YES;
}

- (nullable instancetype)initWithName:(NSString *)name logicalWidth:(NSUInteger)width
                      logicalHeight:(NSUInteger)height refreshRate:(double)refreshRate
                       serialNumber:(uint32_t)serial
                              error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    NSString *failure = nil;
    if (width < 640 || width > 3840 || height < 400 || height > 2160 ||
        (refreshRate != 30.0 && refreshRate != 60.0)) {
        failure = @"虚拟 HiDPI 屏幕范围：640–3840 × 400–2160，刷新率 30 或 60 Hz。";
    } else if (!CDVirtualDisplay.available) {
        failure = @"当前系统未提供兼容的 CGVirtualDisplay 接口。物理屏模式切换仍可使用。";
    }
    if (!failure) {
        @try {
            id descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
            [descriptor setQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)];
            [descriptor setName:name];
            [descriptor setMaxPixelsWide:(unsigned int)width * 2];
            [descriptor setMaxPixelsHigh:(unsigned int)height * 2];
            [descriptor setSizeInMillimeters:CGSizeMake(width * 2 * 25.4 / 220,
                                                        height * 2 * 25.4 / 220)];
            [descriptor setRedPrimary:CGPointMake(0.64, 0.33)];
            [descriptor setGreenPrimary:CGPointMake(0.30, 0.60)];
            [descriptor setBluePrimary:CGPointMake(0.15, 0.06)];
            [descriptor setWhitePoint:CGPointMake(0.3127, 0.3290)];
            [descriptor setVendorID:0x4344]; // ClearDisplay's own software identity.
            [descriptor setProductID:1];
            [descriptor setSerialNum:serial];
            if ([descriptor respondsToSelector:@selector(setSerialNumber:)]) {
                [descriptor setSerialNumber:serial];
            }
            _display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
            if (!_display) {
                failure = @"macOS 拒绝创建虚拟屏幕。请确认本地图形会话可用。";
            } else {
                id settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
                [settings setHiDPI:1];
                NSMutableArray *modes = [NSMutableArray array];
                // The first mode is the requested logical size. Extra modes allow
                // switching scale without deleting and recreating the display.
                NSArray *sizes = @[@[@(width), @(height)], @[@1280, @720], @[@1600, @900],
                                   @[@1920, @1080], @[@2560, @1440], @[@3200, @1800]];
                NSMutableSet *seen = [NSMutableSet set];
                for (NSArray<NSNumber *> *size in sizes) {
                    unsigned int w = size[0].unsignedIntValue, h = size[1].unsignedIntValue;
                    NSString *key = [NSString stringWithFormat:@"%ux%u", w, h];
                    if (w > width || h > height || [seen containsObject:key]) continue;
                    [seen addObject:key];
                    id mode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc]
                        initWithWidth:w height:h refreshRate:refreshRate];
                    if (mode) [modes addObject:mode];
                }
                [settings setModes:modes];
                if (![_display applySettings:settings]) {
                    failure = @"macOS 拒绝应用虚拟屏的 HiDPI 模式。";
                    _display = nil;
                }
            }
        } @catch (NSException *exception) {
            _display = nil;
            failure = [NSString stringWithFormat:@"系统虚拟屏接口不兼容：%@", exception.reason];
        }
    }
    if (failure) {
        if (error) *error = [NSError errorWithDomain:@"ClearDisplay.Virtual" code:1
                userInfo:@{NSLocalizedDescriptionKey:failure}];
        return nil;
    }
    return self;
}

- (CGDirectDisplayID)displayID { return [_display displayID]; }
@end
