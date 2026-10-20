#import <UIKit/UIKit.h>

// 私有类：Preferences.framework。不链接该框架，靠 -Wl,-undefined,dynamic_lookup 在设置进程里解析。
@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
@end

@interface PSListController : UIViewController <UITableViewDataSource, UITableViewDelegate> {
	@protected
	NSArray *_specifiers;       // ⚠️ 必须声明在基类接口里：数据源直接访问这个 ivar
}
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (UITableView *)table;
@end

@interface IBRootListController : PSListController
@end
