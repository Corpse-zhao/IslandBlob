#import "IBBlobWindow.h"

// 版本号唯一来源（日志 / 面板 / control 三处必须一致）
static NSString * const kIBVersion = @"0.4.5";

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

#pragma mark - 用户调节（CFPreferences 偏好域，与设置面板原生读写同一域）

static CFStringRef const kIBDomain = CFSTR("com.corpse.islandblob");

static BOOL IBReadEnabled(void)
{
	CFPreferencesAppSynchronize(kIBDomain);
	CFTypeRef v = CFPreferencesCopyAppValue(CFSTR("enabled"), kIBDomain);
	BOOL on = YES;                      // 未配置 => 默认开启
	if (v) {
		on = [(__bridge NSNumber *)v boolValue];
		CFRelease(v);
	}
	return on;
}

static CGFloat IBPrefNumber(NSString *key, CGFloat def, CGFloat min, CGFloat max)
{
	CFPreferencesAppSynchronize(kIBDomain);
	CFTypeRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, kIBDomain);
	CGFloat f = def;
	if (v) {
		f = (CGFloat)[(__bridge NSNumber *)v doubleValue];
		CFRelease(v);
	}
	if (f < min) f = min;
	if (f > max) f = max;
	return f;
}

// 读取调节参数；全部做范围钳制，坏值一律回落默认
// ⭐ 0.4.2 起只保留等比缩放：sx = sy = sizeScale，形状永不拉伸变形。
//    0.4.x 的 lengthScale / widthScale（异比拉伸）已废弃，读到也一律忽略。
static void IBReadLook(CGFloat *sx, CGFloat *sy, CGFloat *ox, CGFloat *oy)
{
	CGFloat size = IBPrefNumber(@"sizeScale", 1.0, 0.3, 3.0);
	CGFloat dx   = IBPrefNumber(@"offsetX", 0.0, -200.0, 200.0);
	CGFloat dy   = IBPrefNumber(@"offsetY", 0.0, -120.0, 120.0);

	*sx = size;
	*sy = size;
	*ox = dx;
	*oy = dy;
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
// 几何（pt，y 相对屏幕顶）—— ⭐ 0.4.5：
//   · 横杠 y27..62，长 126pt = 与灵动岛本体等长（用户要求"跟灵动岛一样长"），圆角 = 高/2
//   · 左上瓣 d48：圆心高于横杠中线 6.7pt，探出横杠上缘、压住横杠左端
//   · 左下瓣 d40：小一号，圆心低于中线 11.7pt，垂在横杠下方
//   · 右端"桃屁股"：**不是圆球**。两瓣（上下各一元）横向错开、中间留内凹缺口，
//     右缘形成"瓣-凹-瓣"的桃子屁股轮廓（心形旋转 90° 朝右的下半）
//   参考图 430×155 像素测量换算（k≈0.427），整体水平不旋转
static NSArray<UIBezierPath *> *IBBlobSubPaths(CGFloat width, CGFloat sx, CGFloat sy, CGFloat ox, CGFloat oy)
{
	CGFloat cx = width / 2.0;
	NSMutableArray<UIBezierPath *> *paths = [NSMutableArray array];

	// 用户调节：以 (cx, 45) 为锚点（屏幕水平中心 + 形状纵向中心）等比缩放 + 平移（sx == sy，永不变形）
	CGAffineTransform t = CGAffineTransformMakeTranslation(cx + ox, 45.0 + oy);
	t = CGAffineTransformScale(t, sx, sy);
	t = CGAffineTransformTranslate(t, -cx, -45.0);

	// 左上瓣（大，探出横杠上缘）
	{
		UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 100.0, 13.8, 48.0, 48.0)];
		[path applyTransform:t];
		[paths addObject:path];
	}
	// 左下瓣（小一号，偏左下，垂在横杠下方）
	{
		UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 98.0, 36.2, 40.0, 40.0)];
		[path applyTransform:t];
		[paths addObject:path];
	}

	// 中间横杠（长 126pt = 灵动岛本体长度，圆角 17.5）
	{
		UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(cx - 63.0, 27.0, 126.0, 35.0)
														cornerRadius:17.5];
		[path applyTransform:t];
		[paths addObject:path];
	}

	// 右端"桃屁股"：单一路径（两瓣融合 + 右缘中浅凹口），上下各凸出横杠 5pt，
	// 最右凸出横杠右缘约 30pt；起止点藏在横杠内部，衔接无缝
	UIBezierPath *butt = [UIBezierPath bezierPath];
	[butt moveToPoint:CGPointMake(cx + 55.0, 28.0)];                         // 起点（藏于横杠内）
	[butt addCurveToPoint:CGPointMake(cx + 76.0, 22.0)                      // 上瓣顶
	   controlPoint1:CGPointMake(cx + 62.0, 28.0)
	   controlPoint2:CGPointMake(cx + 64.0, 22.0)];
	[butt addCurveToPoint:CGPointMake(cx + 88.0, 44.5)                      // 右缘中凹点
	   controlPoint1:CGPointMake(cx + 86.0, 22.0)
	   controlPoint2:CGPointMake(cx + 94.0, 36.0)];
	[butt addCurveToPoint:CGPointMake(cx + 76.0, 67.0)                      // 下瓣底
	   controlPoint1:CGPointMake(cx + 94.0, 53.0)
	   controlPoint2:CGPointMake(cx + 86.0, 67.0)];
	[butt addCurveToPoint:CGPointMake(cx + 55.0, 61.0)                      // 回到横杠内
	   controlPoint1:CGPointMake(cx + 64.0, 67.0)
	   controlPoint2:CGPointMake(cx + 62.0, 61.0)];
	[butt closePath];
	[butt applyTransform:t];
	[paths addObject:butt];

	return paths;
}

#pragma mark - 团块视图

@interface IBBlobView : UIView {
	CGFloat _builtWidth;
	CGFloat _builtSx;
	CGFloat _builtSy;
	CGFloat _builtOx;
	CGFloat _builtOy;
}
@property (nonatomic, assign) CGFloat lookSx;
@property (nonatomic, assign) CGFloat lookSy;
@property (nonatomic, assign) CGFloat lookOx;
@property (nonatomic, assign) CGFloat lookOy;
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
	// 宽度或五项调节参数没变就不重建：避免每 0.5 秒反复毁建图层
	if (_builtWidth > 0.0 && fabs(width - _builtWidth) < 0.5
		&& fabs(self.lookSx - _builtSx) < 0.001 && fabs(self.lookSy - _builtSy) < 0.001
		&& fabs(self.lookOx - _builtOx) < 0.01 && fabs(self.lookOy - _builtOy) < 0.01) return;
	_builtWidth = width;
	_builtSx = self.lookSx;
	_builtSy = self.lookSy;
	_builtOx = self.lookOx;
	_builtOy = self.lookOy;

	// ⚠️ 必须先拷贝再删：直接遍历 self.layer.sublayers 同时 removeFromSuperlayer
	//    会触发"集合在枚举中被修改"异常 → SpringBoard 崩溃 → 安全模式（0.2.0 实锤）
	NSArray<CALayer *> *existing = [[self.layer sublayers] copy];
	for (CALayer *old in existing) {
		[old removeFromSuperlayer];
	}

	for (UIBezierPath *path in IBBlobSubPaths(width, self.lookSx, self.lookSy, self.lookOx, self.lookOy)) {
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
			// 用户调节参数：每轮读取、有变化才触发重建
			CGFloat sx, sy, ox, oy;
			IBReadLook(&sx, &sy, &ox, &oy);
			if (fabs(blob.lookSx - sx) > 0.001 || fabs(blob.lookSy - sy) > 0.001
				|| fabs(blob.lookOx - ox) > 0.01 || fabs(blob.lookOy - oy) > 0.01) {
				blob.lookSx = sx;
				blob.lookSy = sy;
				blob.lookOx = ox;
				blob.lookOy = oy;
				[blob setNeedsLayout];
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
