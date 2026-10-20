#import "IBBlobWindow.h"

// 版本号唯一来源（日志 / 面板 / control 三处必须一致）
static NSString * const kIBVersion = @"0.2.1";

static NSString * const kIBPrefDir  = @"/var/mobile/Documents/IslandBlob";
static NSString * const kIBPrefPath = @"/var/mobile/Documents/IslandBlob/config.plist";

#pragma mark - 日志（追加式，256KB 封顶）

static void IBLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void IBLog(NSString *fmt, ...)
{
	va_list args;
	va_start(args, fmt);
	NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
	va_end(args);

	NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];

	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:kIBPrefDir]) {
		[fm createDirectoryAtPath:kIBPrefDir withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	NSDictionary *attr = [fm attributesOfItemAtPath:kIBPrefPath error:NULL];
	unsigned long long size = attr ? [attr fileSize] : 0ULL;
	NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
	if (size > 256ULL * 1024ULL) {
		[data writeToFile:kIBPrefPath atomically:YES];
	} else {
		NSFileHandle *h = [NSFileHandle fileHandleForUpdatingAtPath:kIBPrefPath];
		if (h) {
			[h seekToEndOfFile];
			[h writeData:data];
			[h closeFile];
		} else {
			[data writeToFile:kIBPrefPath atomically:YES];
		}
	}

	NSLog(@"[IslandBlob] %@", msg);
}

#pragma mark - 开关读取（被 prefs 面板写入的同一份文件）

static BOOL IBReadEnabled(void)
{
	NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kIBPrefPath];
	if (!d) return YES;                 // 未配置 => 默认开启
	id v = d[@"enabled"];
	return v ? [v boolValue] : YES;
}

#pragma mark - 启动崩溃熔断
//
// 插件一旦在 SpringBoard 里崩，系统会进安全模式；若每次重载都崩，用户会被锁在安全模式里反复折腾。
// 这里做计数：20 秒内重复启动视为"上次崩溃了"，累计 3 次就不再挂载（仅写日志），
// 保证手机一定能用；用户删包/注销后计数文件（startup.plist）会被清掉自然恢复。
static BOOL IBCrashGuardAllowsStart(void)
{
	NSString *path = [kIBPrefDir stringByAppendingPathComponent:@"startup.plist"];
	NSDictionary *prev = [NSDictionary dictionaryWithContentsOfFile:path];
	double now = [NSDate date].timeIntervalSince1970;
	double last = prev[@"last"] ? [prev[@"last"] doubleValue] : 0.0;
	int count = prev[@"count"] ? [prev[@"count"] intValue] : 0;
	count = (now - last < 20.0) ? (count + 1) : 1;

	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:kIBPrefDir]) {
		[fm createDirectoryAtPath:kIBPrefDir withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	[@{@"last": @(now), @"count": @(count)} writeToFile:path atomically:YES];

	if (count >= 3) {
		IBLog(@"[熔断] 20 秒内第 %d 次启动 → 判定上次崩溃，本次不挂载（手机可正常使用）", count);
		return NO;
	}
	return YES;
}

#pragma mark - 窗口工具

static NSArray<UIWindow *> *IBAllWindows(void)
{
	NSMutableArray<UIWindow *> *out = [NSMutableArray array];
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) continue;
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w && ![out containsObject:w]) [out addObject:w];
		}
	}
	for (UIWindow *w in UIApplication.sharedApplication.windows) {
		if (w && ![out containsObject:w]) [out addObject:w];
	}
	return out;
}

static UIWindow *IBKeyWindow(void)
{
	for (UIWindow *w in IBAllWindows()) {
		if (w.isKeyWindow) return w;
	}
	return nil;
}

#pragma mark - 团块子路径（每块独立一层，杜绝 nonzero 绕向相反导致的"挖空"）
//
// ⚠️ 0.1.x 的教训：椭圆子路径与圆角矩形/手绘贝塞尔的绕向相反，
//    appendPath 进同一条路径后 nonzero 规则会把重叠区填成透明洞。
//    0.2.0 起每块形状单独一个 CAShapeLayer，黑上叠黑，永不露底。
//
// 几何（pt，y 相对屏幕顶）：
//   · 横杠 y10..52：完整盖住灵动岛（y11..48），比 0.1.x 上移加高
//   · 左端双球 d40：y14/36，探出横杠左缘
//   · 右端桃形头：平滑心形（六段三次贝塞尔）+ r9.2 圆帽钝尖
static NSArray<UIBezierPath *> *IBBlobSubPaths(CGFloat width)
{
	CGFloat cx = width / 2.0;
	NSMutableArray<UIBezierPath *> *paths = [NSMutableArray array];

	// 左端双球（爱心瓣）
	[paths addObject:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 95.0, 14.0, 40.0, 40.0)]];
	[paths addObject:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 95.0, 36.0, 40.0, 40.0)]];

	// 中间粗横杠（上移加高，完整覆盖灵动岛）
	[paths addObject:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(cx - 88.0, 10.0, 140.0, 42.0)
												cornerRadius:21.0]];

	// 右端桃形头：平滑心形
	UIBezierPath *heart = [UIBezierPath bezierPath];
	[heart moveToPoint:CGPointMake(cx + 97.5, 41.7)];                        // 上缘进圆帽处
	[heart addCurveToPoint:CGPointMake(cx + 55.1, 13.1)                      // 上瓣顶
	   controlPoint1:CGPointMake(cx + 85.0, 27.5)
	   controlPoint2:CGPointMake(cx + 68.7, 13.1)];
	[heart addCurveToPoint:CGPointMake(cx + 34.8, 36.9)                      // 上瓣左侧
	   controlPoint1:CGPointMake(cx + 40.2, 13.1)
	   controlPoint2:CGPointMake(cx + 34.8, 26.7)];
	[heart addCurveToPoint:CGPointMake(cx + 47.0, 47.0)                      // 中腰凹口（切线连续）
	   controlPoint1:CGPointMake(cx + 34.8, 42.3)
	   controlPoint2:CGPointMake(cx + 40.2, 47.0)];
	[heart addCurveToPoint:CGPointMake(cx + 34.8, 57.3)                      // 下瓣左侧
	   controlPoint1:CGPointMake(cx + 40.2, 47.0)
	   controlPoint2:CGPointMake(cx + 34.8, 51.8)];
	[heart addCurveToPoint:CGPointMake(cx + 55.1, 80.9)                      // 下瓣底
	   controlPoint1:CGPointMake(cx + 34.8, 67.4)
	   controlPoint2:CGPointMake(cx + 40.2, 80.9)];
	[heart addCurveToPoint:CGPointMake(cx + 97.5, 52.3)                      // 下缘进圆帽处
	   controlPoint1:CGPointMake(cx + 68.7, 80.9)
	   controlPoint2:CGPointMake(cx + 83.0, 68.0)];
	[heart closePath];
	[paths addObject:heart];

	// 尖端圆帽（右缘 = 纯圆弧）
	[paths addObject:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx + 80.8, 37.8, 18.4, 18.4)]];

	return paths;
}

#pragma mark - 团块视图

@interface IBBlobView : UIView
@end

@interface IBBlobView : UIView {
	CGFloat _builtWidth;
}
@end

@implementation IBBlobView

- (instancetype)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		self.userInteractionEnabled = NO;
		self.backgroundColor = [UIColor clearColor];
		self.opaque = NO;
		_builtWidth = 0.0;
	}
	return self;
}

- (void)layoutSubviews
{
	[super layoutSubviews];

	CGFloat width = self.bounds.size.width;
	if (width < 1.0) return;
	// 宽度没变就不重建：0.5s 一轮的守护循环会反复 setNeedsLayout，重建层没必要且易出事
	if (_builtWidth > 0.0 && fabs(width - _builtWidth) < 0.5) return;
	_builtWidth = width;

	// ⚠️ 必须先拷贝再删：直接遍历 self.layer.sublayers 同时 removeFromSuperlayer
	//    会触发"集合在枚举中被修改"异常 → SpringBoard 崩溃 → 安全模式（0.2.0 实锤）
	NSArray<CALayer *> *existing = [[self.layer sublayers] copy];
	for (CALayer *old in existing) {
		[old removeFromSuperlayer];
	}

	for (UIBezierPath *path in IBBlobSubPaths(width)) {
		CAShapeLayer *shape = [CAShapeLayer layer];
		shape.fillColor = [UIColor blackColor].CGColor;
		shape.strokeColor = nil;
		shape.frame = self.bounds;
		shape.path = path.CGPath;
		[self.layer addSublayer:shape];
	}
}

@end

#pragma mark - 管理器

@interface IBBlobManager ()
@property (nonatomic, strong) NSMutableArray<UIWindow *> *windows;
@property (nonatomic, assign) BOOL loggedOn;
@end

@implementation IBBlobManager

+ (instancetype)shared
{
	static IBBlobManager *instance = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		instance = [[IBBlobManager alloc] init];
	});
	return instance;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_windows = [NSMutableArray array];
	}
	return self;
}

- (void)start
{
	IBLog(@"========== IslandBlob %@ 启动（常驻 + 开关）==========", kIBVersion);
	IBLog(@"[配置] 当前开关=%d（文件 %@）", IBReadEnabled() ? 1 : 0, kIBPrefPath);

	if (!IBCrashGuardAllowsStart()) {
		return;                     // 熔断：手机保持可用，日志里能看到原因
	}

	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[weakSelf tick];
		[NSTimer scheduledTimerWithTimeInterval:0.5 target:weakSelf
									   selector:@selector(tickTimer:)
									   userInfo:nil repeats:YES];
	});
}

- (void)tickTimer:(NSTimer *)timer
{
	[self tick];
}

- (void)tick
{
	// tick 跑在 SpringBoard 主线程上，任何异常都会直接把桌面送进安全模式 —— 全部兜住
	@try {
		[self tickInside];
	} @catch (NSException *e) {
		IBLog(@"[异常] tick 抛出 %@: %@（已吞掉，避免安全模式）", e.name, e.reason);
	}
}

- (void)tickInside
{
	BOOL on = IBReadEnabled();

	if (!on) {
		if (self.windows.count > 0) {
			[self removeAllWindows];
			IBLog(@"[开关] 已关闭 → 团块窗口全部撤下");
		}
		self.loggedOn = NO;
		return;
	}

	// 先把窗口集合收拢（去掉已断开场景的）
	NSMutableArray<UIWindowScene *> *scenes = [NSMutableArray array];
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) continue;
		[scenes addObject:(UIWindowScene *)scene];
	}

	for (NSInteger i = (NSInteger)self.windows.count - 1; i >= 0; i--) {
		UIWindow *w = self.windows[(NSUInteger)i];
		BOOL alive = w.windowScene ? [scenes containsObject:(UIWindowScene *)w.windowScene] : NO;
		if (alive) continue;
		w.hidden = YES;
		w.rootViewController = nil;
		w.windowScene = nil;
		[self.windows removeObjectAtIndex:(NSUInteger)i];
		IBLog(@"[移除] 场景已断开 → 销毁一个团块窗口（剩余 %lu）", (unsigned long)self.windows.count);
	}

	for (UIWindowScene *scene in scenes) {
		UIWindow *w = [self windowForScene:scene];
		if (!w) {
			w = [self createWindowForScene:scene];
			if (!w) continue;
		}
		w.hidden = NO;
		CGRect bounds = w.bounds;
		if (bounds.size.width < 1.0) continue;

		UIView *host = w.rootViewController.view;
		if (!CGRectEqualToRect(host.frame, bounds)) {
			host.frame = bounds;
		}
		IBBlobView *blob = (IBBlobView *)host.subviews.firstObject;
		if (blob && ![blob isKindOfClass:[IBBlobView class]]) blob = nil;
		if (blob) {
			CGRect wanted = CGRectMake(0.0, 0.0, bounds.size.width, 96.0);
			if (!CGRectEqualToRect(blob.frame, wanted)) {
				blob.frame = wanted;         // 尺寸真的变了才动，避免每轮无效布局
			}
		}
	}

	if (!self.loggedOn && self.windows.count > 0) {
		UIWindow *w = self.windows.firstObject;
		IBLog(@"[安装] 团块窗口就绪：数量=%lu 尺寸=%@ level=%.0f",
			  (unsigned long)self.windows.count,
			  NSStringFromCGSize(w.bounds.size), w.windowLevel);
		self.loggedOn = YES;
	}
}

- (UIWindow *)windowForScene:(UIWindowScene *)scene
{
	for (UIWindow *w in self.windows) {
		if (w.windowScene == scene) return w;
	}
	return nil;
}

- (UIWindow *)createWindowForScene:(UIWindowScene *)scene
{
	UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
	if (!w) return nil;

	w.windowLevel = 10000.0;                 // 高于 App / 弹窗 / 锁屏，低于系统状态栏层
	w.backgroundColor = [UIColor clearColor];
	w.opaque = NO;
	w.userInteractionEnabled = NO;           // 整窗不吃触摸
	w.rootViewController = nil;

	UIViewController *host = [[UIViewController alloc] init];
	host.view.backgroundColor = [UIColor clearColor];
	host.view.opaque = NO;
	host.view.userInteractionEnabled = NO;

	IBBlobView *blob = [[IBBlobView alloc] initWithFrame:CGRectMake(0.0, 0.0, w.bounds.size.width, 96.0)];
	blob.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[host.view addSubview:blob];

	w.rootViewController = host;

	UIWindow *prevKey = IBKeyWindow();
	w.hidden = NO;                           // ⚠️ 绝不 makeKeyAndVisible
	if (w.isKeyWindow && prevKey) {
		[prevKey makeKeyWindow];             // 万一抢到了 key window，立刻还回去
		IBLog(@"[安全] 意外成为 key window → 已归还给系统");
	}

	[self.windows addObject:w];
	return w;
}

- (void)removeAllWindows
{
	for (UIWindow *w in self.windows) {
		w.hidden = YES;
		w.rootViewController = nil;
		w.windowScene = nil;
	}
	[self.windows removeAllObjects];
}

@end
