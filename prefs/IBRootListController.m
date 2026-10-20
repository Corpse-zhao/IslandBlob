#import "IBRootListController.h"

static NSString * const kIBPrefDirPath = @"/var/mobile/Documents/IslandBlob";

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

// ⭐ 0.4.0 起滑条/开关全部走系统原生链路：Root.plist 里每个格子声明
//    defaults=com.corpse.islandblob + key，PSListController 自己读写 NSUserDefaults
//    （0.3.x 自定义 read/setPreferenceValue 对 PSSliderCell 不生效，已废弃）。
//    插件侧用 CFPreferences 每 0.5 秒读同一偏好域。
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

- (void)resetDefaults:(PSSpecifier *)specifier
{
	NSUserDefaults *defs = [[NSUserDefaults alloc] initWithSuiteName:@"com.corpse.islandblob"];
	// 0.4.2 起只有等比大小 + 两个偏移；顺带清掉 0.4.x 遗留的拉伸参数，避免旧值残留
	[defs setDouble:1.0 forKey:@"sizeScale"];
	[defs setDouble:0.0 forKey:@"offsetX"];
	[defs setDouble:0.0 forKey:@"offsetY"];
	[defs removeObjectForKey:@"lengthScale"];
	[defs removeObjectForKey:@"widthScale"];
	IBWriteLog(@"已恢复默认：等比大小 1.0 / 偏移 0（已清除废弃的拉伸参数）");
	[self reloadSpecifiers];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	IBWriteLog([NSString stringWithFormat:@"面板已加载：title=%@（设置进程能看到本行 = 入口正常）",
				self.title ?: self.navigationItem.title ?: @"(nil)"]);
}

@end
