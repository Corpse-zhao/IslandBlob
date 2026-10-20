#import <UIKit/UIKit.h>
#import "IBBlobWindow.h"

%ctor {
	@autoreleasepool {
		NSString *bid = [NSBundle mainBundle].bundleIdentifier;
		if (![bid isEqualToString:@"com.apple.springboard"]) return;
		[[IBBlobManager shared] start];
	}
}
