#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *kFBSKeyEnabled = @"fbs_enabled";
static NSString *kFBSKeyHaptic  = @"fbs_haptic";
static NSString *kFBSKeyStrength = @"fbs_strength";

static BOOL FBSGetEnabled(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    id v = [d objectForKey:kFBSKeyEnabled];
    return v ? [v boolValue] : YES;
}
static BOOL FBSGetHaptic(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    id v = [d objectForKey:kFBSKeyHaptic];
    return v ? [v boolValue] : YES;
}
static double FBSGetStrength(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    id v = [d objectForKey:kFBSKeyStrength];
    return v ? [v doubleValue] : 0.8;
}

@interface FBSPanGesture : UIPanGestureRecognizer
@end
@implementation FBSPanGesture
@end

@interface FBSHaptic : NSObject
+ (instancetype)shared;
- (void)track:(UIPanGestureRecognizer *)g;
@end
@implementation FBSHaptic
{
    UIImpactFeedbackGenerator *_gen;
}
+ (instancetype)shared {
    static FBSHaptic *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [FBSHaptic new]; });
    return s;
}
- (void)track:(UIPanGestureRecognizer *)g {
    if (!FBSGetHaptic()) return;
    CGFloat w = [UIScreen mainScreen].bounds.size.width;
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            _gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
            [_gen prepare];
            break;
        case UIGestureRecognizerStateEnded: {
            CGFloat tx = [g translationInView:g.view].x;
            CGFloat vx = [g velocityInView:g.view].x;
            if (tx > w * 0.35 || vx > 300) {
                double s = FBSGetStrength();
                if (s < 0.01) s = 0.01;
                if (s > 1.0) s = 1.0;
                [_gen impactOccurredWithIntensity:s];
            }
            _gen = nil;
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            _gen = nil;
            break;
        default: break;
    }
}
@end

@interface FBSDelegate : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
@end
@implementation FBSDelegate
+ (instancetype)shared {
    static FBSDelegate *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [FBSDelegate new]; });
    return s;
}
- (UINavigationController *)navOf:(UIView *)v {
    UIResponder *r = v.nextResponder;
    while (r) {
        if ([r isKindOfClass:[UINavigationController class]]) return (id)r;
        if ([r isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (id)r;
            if (vc.navigationController) return vc.navigationController;
        }
        r = r.nextResponder;
    }
    return nil;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (!FBSGetEnabled()) return NO;
    if (![g isKindOfClass:[UIPanGestureRecognizer class]]) return NO;
    UIPanGestureRecognizer *p = (id)g;
    UINavigationController *nav = [self navOf:g.view];
    if (!nav || nav.viewControllers.count < 2) return NO;
    CGPoint t = [p translationInView:g.view];
    if (t.x < 2) return NO;
    if (fabs(t.x) < fabs(t.y)) return NO;
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o {
    return NO;
}
@end

static void FBSInstallOnNav(UINavigationController *nav) {
    @try {
        for (UIGestureRecognizer *g in nav.view.gestureRecognizers) {
            if ([g isMemberOfClass:[FBSPanGesture class]]) return;
        }
        UIGestureRecognizer *sys = nav.interactivePopGestureRecognizer;
        NSArray *targets = [sys valueForKey:@"_targets"];
        id wrapper = targets.firstObject;
        if (!wrapper) return;
        id target = [wrapper valueForKey:@"_target"];
        if (!target) return;
        FBSPanGesture *gesture = [[FBSPanGesture alloc] initWithTarget:target
                                                               action:NSSelectorFromString(@"handleNavigationTransition:")];
        gesture.delegate = [FBSDelegate shared];
        gesture.maximumNumberOfTouches = 1;
        [gesture addTarget:[FBSHaptic shared] action:@selector(track:)];
        [nav.view addGestureRecognizer:gesture];
    } @catch (NSException *e) {}
}

static void FBSWalk(UIViewController *vc) {
    if (!vc) return;
    if ([vc isKindOfClass:[UINavigationController class]]) {
        FBSInstallOnNav((id)vc);
    }
    for (UIViewController *c in vc.childViewControllers) FBSWalk(c);
}

static UIViewController *FBSTopVC(void) {
    UIWindowScene *ws = nil;
    for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) { ws = s; break; }
    }
    if (!ws) return nil;
    UIViewController *vc = ws.windows.firstObject.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static void FBSShowSettings(void) {
    UIViewController *top = FBSTopVC();
    if (!top) return;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"全屏返回设置" message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    BOOL en = FBSGetEnabled();
    [ac addAction:[UIAlertAction actionWithTitle:en ? @"✓ 全屏返回: 开" : @"  全屏返回: 关" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        [[NSUserDefaults standardUserDefaults] setBool:!en forKey:kFBSKeyEnabled];
    }]];

    BOOL ha = FBSGetHaptic();
    [ac addAction:[UIAlertAction actionWithTitle:ha ? @"✓ 确认震动: 开" : @"  确认震动: 关" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        [[NSUserDefaults standardUserDefaults] setBool:!ha forKey:kFBSKeyHaptic];
    }]];

    double st = FBSGetStrength();
    [ac addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"震动强度: %.0f%%", st*100] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        double next = st + 0.25;
        if (next > 1.0) next = 0.25;
        [[NSUserDefaults standardUserDefaults] setDouble:next forKey:kFBSKeyStrength];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:ac animated:YES completion:nil];
}

@interface FBSBtnTarget : NSObject
+ (instancetype)shared;
- (void)onBtn;
@end
@implementation FBSBtnTarget
+ (instancetype)shared {
    static FBSBtnTarget *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [FBSBtnTarget new]; });
    return s;
}
- (void)onBtn { FBSShowSettings(); }
@end

static void FBSInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in s.windows) {
                if (w.rootViewController) FBSWalk(w.rootViewController);
                static dispatch_once_t once;
                dispatch_once(&once, ^{
                    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
                    btn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 60,
                                           [UIScreen mainScreen].bounds.size.height - 220, 44, 44);
                    btn.layer.cornerRadius = 22;
                    btn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:0.85];
                    [btn setTitle:@"设" forState:UIControlStateNormal];
                    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                    btn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
                    [btn addTarget:[FBSBtnTarget shared] action:@selector(onBtn) forControlEvents:UIControlEventTouchUpInside];
                    [w addSubview:btn];
                });
            }
        }
    });
}

__attribute__((constructor)) static void FBSConstructor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ FBSInstall(); });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:nil
                                                  usingBlock:^(NSNotification *n){ FBSInstall(); }];
}
