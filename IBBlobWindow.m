#import "IBBlobWindow.h"

// 版本号唯一来源（日志 / 面板 / control 三处必须一致）
static NSString * const kIBVersion = @"0.1.5";

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

#pragma mark - 团块路径（1:1 仿用户特写图：左双球 + 粗横杠 + 右端桃形头）
//
// 按特写图量出的比例（总宽 ≈ 182pt，总高 ≈ 62pt）：
//   · 左端：上下两枚 d40 圆球竖向交叠成"爱心瓣"，比横杠略微探出左缘
//   · 中间：一根 140×35 的粗横杠
//   · 右端：桃形头 —— 两枚 d28 圆瓣上下交叠（中腰有凹口）+ 一片收尖的花瓣楔形，
//           尖朝右、上下都比横杠凸出，尖端圆钝（quad 曲线收口）
static UIBezierPath *IBBlobPath(CGFloat width)
{
	CGFloat cx = width / 2.0;
	UIBezierPath *p = [UIBezierPath bezierPath];

	// 左端双球（爱心瓣）
	[p appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 95.0, 14.0, 40.0, 40.0)]];
	[p appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 95.0, 36.0, 40.0, 40.0)]];
	// 中间粗横杠
	[p appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(cx - 88.0, 27.0, 140.0, 35.0)
											 cornerRadius:17.5]];

	// 右端桃形头：上下两枚圆瓣
	[p appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx + 44.0, 20.0, 28.0, 28.0)]];
	[p appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx + 44.0, 46.0, 28.0, 28.0)]];
	// 花瓣楔形（尖朝右，收口圆钝）
	UIBezierPath *wedge = [UIBezierPath bezierPath];
	[wedge moveToPoint:CGPointMake(cx + 50.0, 26.0)];
	[wedge addQuadCurveToPoint:CGPointMake(cx + 87.0, 47.0) controlPoint:CGPointMake(cx + 80.0, 32.0)];
	[wedge addQuadCurveToPoint:CGPointMake(cx + 50.0, 68.0) controlPoint:CGPointMake(cx + 80.0, 62.0)];
	[wedge closePath];
	[p appendPath:wedge];

	return p;
}

#pragma mark - 团块视图

@interface IBBlobView : UIView
@end

@implementation IBBlobView

- (instancetype)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		self.userInteractionEnabled = NO;
		self.backgroundColor = [UIColor clearColor];
		self.opaque = NO;

		CAShapeLayer *shape = [CAShapeLayer layer];
		shape.fillColor = [UIColor blackColor].CGColor;
		shape.strokeColor = nil;
		shape.frame = self.bounds;
		shape.path = IBBlobPath(self.bounds.size.width).CGPath;
		[self.layer addSublayer:shape];
	}
	return self;
}

- (void)layoutSubviews
{
	[super layoutSubviews];

	CAShapeLayer *shape = (CAShapeLayer *)self.layer.sublayers.firstObject;
	if (![shape isKindOfClass:[CAShapeLayer class]]) return;
	shape.frame = self.bounds;
	shape.path = IBBlobPath(self.bounds.size.width).CGPath;
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
		host.frame = bounds;
		IBBlobView *blob = (IBBlobView *)host.subviews.firstObject;
		if (blob && ![blob isKindOfClass:[IBBlobView class]]) blob = nil;
		if (blob) {
			blob.frame = CGRectMake(0.0, 0.0, bounds.size.width, 96.0);
			[blob setNeedsLayout];
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
