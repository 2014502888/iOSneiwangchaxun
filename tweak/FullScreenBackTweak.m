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

@interface FBSSettingsBall : UIView
+ (instancetype)shared;
- (void)show;
@end
@implementation FBSSettingsBall
{
    UIButton *_btn;
}
+ (instancetype)shared {
    static FBSSettingsBall *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [FBSSettingsBall new]; });
    return s;
}
- (instancetype)init {
    CGRect f = [UIScreen mainScreen].bounds;
    self = [super initWithFrame:CGRectMake(f.size.width - 56, f.size.height - 200, 44, 44)];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;

        _btn = [UIButton buttonWithType:UIButtonTypeSystem];
        _btn.frame = self.bounds;
        _btn.layer.cornerRadius = 22;
        _btn.clipsToBounds = YES;
        _btn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:0.85];
        [_btn setTitle:@"设" forState:UIControlStateNormal];
        [_btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _btn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [_btn addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_btn];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [_btn addGestureRecognizer:pan];
    }
    return self;
}
- (void)show {
    if (self.superview) return;
    UIWindowScene *ws = nil;
    for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) { ws = s; break; }
    }
    if (!ws) return;
    for (UIWindow *w in ws.windows) {
        if (w.isKeyWindow && w.rootViewController) {
            [w addSubview:self];
            return;
        }
    }
}
- (void)onPan:(UIPanGestureRecognizer *)p {
    CGPoint tr = [p translationInView:self];
    p.view.center = CGPointMake(p.view.center.x + tr.x, p.view.center.y + tr.y);
    [p setTranslation:CGPointZero inView:self];
}
- (UIViewController *)topVC {
    UIWindowScene *ws = nil;
    for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) { ws = s; break; }
    }
    if (!ws) return nil;
    UIViewController *vc = ws.windows.firstObject.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}
- (void)onTap {
    UIViewController *top = [self topVC];
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

static void FBSInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in s.windows) {
                if (w.rootViewController) FBSWalk(w.rootViewController);
            }
        }
        [[FBSSettingsBall shared] show];
    });
}

__attribute__((constructor)) static void FBSConstructor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ FBSInstall(); });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:nil
                                                  usingBlock:^(NSNotification *n){ FBSInstall(); }];
}
