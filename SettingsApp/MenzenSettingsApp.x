#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <roothide.h>

@interface PSListController (MenzenURL)
- (void)handleURL:(NSDictionary *)url withCompletion:(void (^)(void))completion;
@end

// SpringBoard's link, "prefs:root=Menzen&path=connected", or with Shuffle
// "prefs:root=Menzen/connected".
static BOOL MenzenIsConnectedURL(NSURL *url) {
	if (![url.scheme.lowercaseString isEqualToString:@"prefs"]) return NO;
	NSMutableDictionary<NSString *, NSString *> *query = [NSMutableDictionary dictionary];
	for (NSString *pair in [url.resourceSpecifier componentsSeparatedByString:@"&"]) {
		NSRange equals = [pair rangeOfString:@"="];
		if (equals.location != NSNotFound) query[[pair substringToIndex:equals.location]] = [pair substringFromIndex:NSMaxRange(equals)];
	}

	NSArray<NSString *> *root = [query[@"root"] componentsSeparatedByString:@"/"];
	if (![root.firstObject isEqualToString:@"Menzen"]) return NO;
	return [query[@"path"] isEqualToString:@"connected"] || (root.count > 1 && [root[1] isEqualToString:@"connected"]);
}

static UINavigationController *MenzenNavigationController(UIViewController *controller) {
	if ([controller isKindOfClass:UISplitViewController.class]) {
		UISplitViewController *split = (UISplitViewController *)controller;
		UIViewController *detail = split.isCollapsed ? split.viewControllers.firstObject : [split viewControllerForColumn:UISplitViewControllerColumnSecondary];
		if ([detail isKindOfClass:UINavigationController.class]) return (UINavigationController *)detail;
	}

	for (UIViewController *child in controller.childViewControllers) {
		UINavigationController *navigationController = MenzenNavigationController(child);
		if (navigationController) return navigationController;
	}

	return nil;
}

// The way PreferenceLoader opens a pane here: its controller pushed onto the
// navigation stack, with that as its root controller. Popping to the root
// first would fight SwiftUI, which owns the stack, so it goes on top.
static void MenzenOpenConnected(UIWindowScene *scene, NSUInteger attempt) {
	UINavigationController *navigationController = nil;
	for (UIWindow *window in scene.windows) {
		navigationController = MenzenNavigationController(window.rootViewController);
		if (navigationController) break;
	}

	// At launch the navigation stack comes a moment after the scene.
	if (!navigationController) {
		if (attempt < 20) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				MenzenOpenConnected(scene, attempt + 1);
			});
		}
		return;
	}

	Class rootClass = NSClassFromString(@"MenzenRootListController");
	if (!rootClass) {
		[[NSBundle bundleWithPath:jbroot(@"/Library/PreferenceBundles/MenzenPreferences.bundle")] load];
		rootClass = NSClassFromString(@"MenzenRootListController");
	}
	if (!rootClass) return;

	Class connectedClass = NSClassFromString(@"MenzenConnectedListController");
	if (connectedClass && [navigationController.topViewController isKindOfClass:connectedClass]) return;

	PSListController *root = (PSListController *)navigationController.topViewController;
	if (![root isKindOfClass:rootClass]) {
		PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:@"Menzen" target:nil set:nil get:nil detail:rootClass cell:PSLinkCell edit:nil];
		specifier.identifier = @"Menzen";
		root = [rootClass new];
		root.rootController = (id)navigationController;
		root.specifier = specifier;
		[navigationController pushViewController:root animated:NO];
	}

	[root handleURL:@{@"root": @"Menzen", @"path": @"connected"} withCompletion:nil];
}

static void MenzenOpenIfConnected(UIScene *scene, NSSet<UIOpenURLContext *> *contexts) {
	if (![scene isKindOfClass:UIWindowScene.class]) return;
	for (UIOpenURLContext *context in contexts) {
		if (!MenzenIsConnectedURL(context.URL)) continue;
		dispatch_async(dispatch_get_main_queue(), ^{
			MenzenOpenConnected((UIWindowScene *)scene, 0);
		});
		return;
	}
}

// SwiftUI's own scene delegate, which Settings only uses where it's SwiftUI.
%hook MenzenSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
	%orig;
	MenzenOpenIfConnected(scene, options.URLContexts);
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)contexts {
	%orig;
	MenzenOpenIfConnected(scene, contexts);
}

%end

%ctor {
	Class sceneDelegate = objc_getClass("SwiftUI.AppSceneDelegate");
	if (sceneDelegate) %init(MenzenSceneDelegate = sceneDelegate);
}
