#import <UIKit/UIKit.h>

@interface IBBlobManager : NSObject

+ (instancetype)shared;

/// 启动守护循环（3 秒后开始，0.5 秒一轮）
- (void)start;

@end
