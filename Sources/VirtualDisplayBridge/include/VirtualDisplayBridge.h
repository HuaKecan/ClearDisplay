#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Owns a process-local virtual display. Releasing this object removes the display.
@interface CDVirtualDisplay : NSObject
@property(class, nonatomic, readonly) BOOL available;
@property(nonatomic, readonly) CGDirectDisplayID displayID;
- (nullable instancetype)initWithName:(NSString *)name
                       logicalWidth:(NSUInteger)width
                      logicalHeight:(NSUInteger)height
                        refreshRate:(double)refreshRate
                       serialNumber:(uint32_t)serial
                              error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
