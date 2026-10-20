#import "IBRootListController.h"

static NSString * const kIBPrefDirPath  = @"/var/mobile/Documents/IslandBlob";
static NSString * const kIBPrefFilePath = @"/var/mobile/Documents/IslandBlob/config.plist";

static void IBWriteLog(NSString *message)
{
	NSString *line = [NSString stringWithFormat:@"%@ [prefs] %@\n", [NSDate date], message];
	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:kIBPrefDirPath]) {
		[fm createDirectoryAtPath:kIBPrefDirPath withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	NSString *path = [kIBPrefDirPath stringByAppendingPathComponent:@"probe.txt"];
	NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
	NSFileHandle *h = [NSFileHandle fileHandleForUpdatingAtPath:path];
	if (h) {
		[h seekToEndOfFile];
		[h writeData:data];
		[h closeFile];
	} else {
		[data writeToFile:path atomically:YES];
	}
}

static BOOL IBReadEnabled(void)
{
	NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kIBPrefFilePath];
	if (!d) return YES;
	id v = d[@"enabled"];
	return v ? [v boolValue] : YES;
}

#pragma mark - 滑条参数（key → 默认值 / 范围）

static NSDictionary *IBSliderSpec(void)
{
	return @{
		@"sizeScale"   : @[@0.5, @2.0, @1.0],     // [min, max, default]
		@"lengthScale" : @[@0.5, @2.0, @1.0],
		@"widthScale"  : @[@0.5, @2.0, @1.0],
		@"offsetX"     : @[@-150.0, @150.0, @0.0],
		@"offsetY"     : @[@-80.0, @80.0, @0.0],
	};
}

static CGFloat IBReadNumber(NSString *key)
{
	NSArray *spec = IBSliderSpec()[key];
	if (!spec) return 0.0;
	NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kIBPrefFilePath];
	id v = d[key];
	CGFloat f = ([v respondsToSelector:@selector(doubleValue)]) ? (CGFloat)[v doubleValue]
															   : (CGFloat)[spec[2] doubleValue];
	CGFloat min = [spec[0] doubleValue];
	CGFloat max = [spec[1] doubleValue];
	if (f < min) f = min;
	if (f > max) f = max;
	return f;
}

static void IBWriteNumber(NSString *key, CGFloat value)
{
	NSArray *spec = IBSliderSpec()[key];
	if (!spec) return;
	CGFloat min = [spec[0] doubleValue];
	CGFloat max = [spec[1] doubleValue];
	if (value < min) value = min;
	if (value > max) value = max;

	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:kIBPrefDirPath]) {
		[fm createDirectoryAtPath:kIBPrefDirPath withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:kIBPrefFilePath];
	if (!d) d = [NSMutableDictionary dictionary];
	d[key] = @(value);
	BOOL ok = [d writeToFile:kIBPrefFilePath atomically:YES];
	IBWriteLog([NSString stringWithFormat:@"滑条 %@ => %.2f（%@）", key, value, ok ? @"成功" : @"失败"]);
}

static void IBWriteEnabled(BOOL on)
{
	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:kIBPrefDirPath]) {
		[fm createDirectoryAtPath:kIBPrefDirPath withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:kIBPrefFilePath];
	if (!d) d = [NSMutableDictionary dictionary];
	d[@"enabled"] = @(on);
	BOOL ok = [d writeToFile:kIBPrefFilePath atomically:YES];
	IBWriteLog([NSString stringWithFormat:@"开关写入 %@ => %@（%@）",
				on ? @"开" : @"关",
				kIBPrefFilePath,
				ok ? @"成功" : @"失败"]);
}

@implementation IBRootListController

// 显式加载 Root.plist：不依赖基类默认实现（部分 iOS 16 上默认路径拿不到 plist → 整页空白）
- (NSArray *)specifiers
{
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
		IBWriteLog([NSString stringWithFormat:@"Root.plist 加载：%lu 条 specifier",
					(unsigned long)_specifiers.count]);
	}
	return _specifiers;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	IBWriteLog([NSString stringWithFormat:@"面板已加载：title=%@（设置进程能看到本行 = 入口正常）",
				self.title ?: self.navigationItem.title ?: @"(nil)"]);
}

- (id)readPreferenceValue:(PSSpecifier *)specifier
{
	NSString *key = [specifier propertyForKey:@"key"];
	if ([key isEqualToString:@"enabled"]) {
		return @(IBReadEnabled());
	}
	if (IBSliderSpec()[key]) {
		return @(IBReadNumber(key));
	}
	return nil;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
	NSString *key = [specifier propertyForKey:@"key"];
	if ([key isEqualToString:@"enabled"]) {
		IBWriteEnabled([value boolValue]);
		return;
	}
	if (IBSliderSpec()[key] && [value respondsToSelector:@selector(doubleValue)]) {
		IBWriteNumber(key, (CGFloat)[value doubleValue]);
	}
}

@end
