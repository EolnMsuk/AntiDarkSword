// antidarkswordprefs/RootListController.m
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/types.h>
#import <sys/wait.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <signal.h>
#import <SpriteKit/SpriteKit.h>
#import <CoreImage/CoreImage.h>

#import "../ADSLogging.h"

#define ADS_PREFS_SUITE @"com.eolnmsuk.antidarkswordprefs"
#define ADS_NOTIF_SAVED CFSTR("com.eolnmsuk.antidarkswordprefs/saved")
#define PROC_PIDPATHINFO_MAXSIZE 1024

extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

static NSString * const kADSDaemonsGroupSentinel = @"DAEMONS_GROUP";

static void ads_kill_all_apps(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t miblen = 4;
    size_t size;
    
    if (sysctl(mib, miblen, NULL, &size, NULL, 0) == -1) return;
    
    struct kinfo_proc *process = malloc(size);
    if (!process) return;
    
    if (sysctl(mib, miblen, process, &size, NULL, 0) == 0) {
        int count = size / sizeof(struct kinfo_proc);
        pid_t my_pid = getpid();
        
        for (int i = 0; i < count; i++) {
            pid_t pid = process[i].kp_proc.p_pid;
            
            // Bypass kernel/daemons (pid <= 0) & protect host process
            if (pid <= 0 || pid == my_pid) continue;
            
            // Zero-initialize buffer to prevent EXC_BAD_ACCESS
            char pathbuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
            
            if (proc_pidpath(pid, pathbuf, sizeof(pathbuf)) > 0) {
                NSString *path = [NSString stringWithUTF8String:pathbuf];
                
                if (path && 
                    [path containsString:@"/Application"] && 
                    ![path containsString:@"Preferences.app"] && 
                    ![path containsString:@"SpringBoard.app"]) {
                    kill(pid, SIGKILL);
                }
            }
        }
    }
    free(process);
}

static NSArray *ads_msg_and_mail_apps(void) {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[
            @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.MailCompositionService",
            @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
            @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram",
            @"ch.protonmail.protonmail", @"org.whispersystems.signal", @"ph.telegra.Telegraph",
            @"com.facebook.Messenger", @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio",
            @"com.microsoft.skype.teams", @"com.tencent.xin", @"com.viber", @"jp.naver.line",
            @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.apple.Passbook"
        ];
    });
    return list;
}

static inline NSUserDefaults *ads_defaults(void) {
    static NSUserDefaults *sharedDefaults = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    });
    return sharedDefaults;
}

static inline void ads_post_notification(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ADS_NOTIF_SAVED, NULL, NULL, YES);
}

static inline BOOL ads_is_ios16(void) {
    return [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;
}

static inline UIColor *ads_color_green(void) {
    if (@available(iOS 13.0, *)) return [[UIColor systemGreenColor] colorWithAlphaComponent:0.15];
    return [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.15];
}

static inline UIColor *ads_color_red(void) {
    if (@available(iOS 13.0, *)) return [[UIColor systemRedColor] colorWithAlphaComponent:0.15];
    return [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.15];
}

static inline NSString *ads_root_path(NSString *path) {
    static void *jbrootFn = NULL;
    static BOOL jbrootIsReal = NO;
    static dispatch_once_t jbrootOnce;
    dispatch_once(&jbrootOnce, ^{
        jbrootFn = dlsym(RTLD_DEFAULT, "jbroot");
        if (jbrootFn) {
            typedef char *(*jbroot_fn)(const char *);
            char *test = ((jbroot_fn)jbrootFn)("/");
            jbrootIsReal = (test != NULL && strcmp(test, "/") != 0);
        }
    });
    if (jbrootIsReal) {
        typedef char *(*jbroot_fn)(const char *);
        char *resolved = ((jbroot_fn)jbrootFn)(path.UTF8String);
        if (resolved) return @(resolved);
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/"])
        return [NSString stringWithFormat:@"/var/jb%@", path];
    return path;
}

@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
- (NSString *)localizedName;
- (NSURL *)bundleURL;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)applicationIsInstalled:(NSString *)appIdentifier;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@interface UITableViewCell (PreferencesUI)
- (id)control;
@end

@interface AntiDarkSwordPrefsRootListController : PSListController
@property (nonatomic, strong) NSArray *cachedDisabledPresetRules;
@property (nonatomic, strong) NSArray *cachedActiveCustomDaemons;
- (NSArray *)autoProtectedItemsForLevel:(NSInteger)level;
- (void)populateDefaultRulesForLevel:(NSInteger)level force:(BOOL)force;
- (NSString *)displayNameForTargetID:(NSString *)targetID;
- (UIImage *)iconForTargetID:(NSString *)targetID;
- (BOOL)isTargetInstalled:(NSString *)targetID;
@end

@interface AntiDarkSwordCreditsController : PSListController
@end

typedef NS_ENUM(NSInteger, ADSGameState) {
    ADSGameStateMenu,
    ADSGameStatePlaying,
    ADSGameStatePaused,
    ADSGameStateDead
};

// --- MINI GAMES ---
@interface ADSGameMenuScene : SKScene
@property (nonatomic, copy) void (^onSelectGame)(NSInteger gameIndex);
@property (nonatomic, copy) void (^exitHandler)(void);
@end

@interface ADSROPStackerScene : SKScene
@property (nonatomic, copy) void (^exitHandler)(void);
@end

// --- EXPLOIT EATER SCENE ---
@interface ADSExploitEaterScene : SKScene
@property (nonatomic, assign) ADSGameState gameState;
@property (nonatomic, strong) NSMutableArray<NSValue *> *snake;
@property (nonatomic, assign) CGPoint food;
@property (nonatomic, assign) CGVector direction;
@property (nonatomic, assign) NSTimeInterval lastTick;
@property (nonatomic, assign) NSInteger score;

@property (nonatomic, strong) SKNode *gameLayer;
@property (nonatomic, strong) SKEffectNode *bloomNode;
@property (nonatomic, strong) SKNode *leaderboardNode;
@property (nonatomic, strong) SKShapeNode *restartOverlay;

@property (nonatomic, strong) SKLabelNode *titleLbl;
@property (nonatomic, strong) SKLabelNode *scoreLbl;
@property (nonatomic, strong) SKLabelNode *startBtn;
@property (nonatomic, strong) SKLabelNode *pauseBtn;
@property (nonatomic, strong) SKLabelNode *closeBtn;
@property (nonatomic, strong) SKLabelNode *highScoreBtn;

@property (nonatomic, copy) void (^exitHandler)(void);
@end

@implementation ADSExploitEaterScene
static const CGFloat kGridSize = 20.0;

// Shifted grid boundaries UP by 1 cell
- (int)minX { return 2; }
- (int)maxX { return (self.size.width / kGridSize) - 2; }
- (int)minY { return 4; } 
- (int)maxY { return (self.size.height / kGridSize) - 3; } 

- (void)didMoveToView:(SKView *)view {
    self.backgroundColor = [UIColor blackColor];
    
    self.bloomNode = [[SKEffectNode alloc] init];
    CIFilter *bloom = [CIFilter filterWithName:@"CIBloom"];
    [bloom setValue:@0.8 forKey:@"inputRadius"];
    [bloom setValue:@1.5 forKey:@"inputIntensity"];
    self.bloomNode.filter = bloom;
    self.bloomNode.shouldEnableEffects = YES;
    [self addChild:self.bloomNode];
    
    self.gameLayer = [SKNode node];
    [self.bloomNode addChild:self.gameLayer];
    
    [self setupGestures:view];
    [self setupUI];
    [self drawWalls];
    
    self.gameState = ADSGameStateMenu;
    self.snake = [NSMutableArray array];
}

- (void)setupUI {
    self.titleLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.titleLbl.text = @"Exploit Eater";
    self.titleLbl.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    self.titleLbl.fontSize = 24;
    self.titleLbl.position = CGPointMake(self.size.width / 2, self.size.height - 15);
    [self.bloomNode addChild:self.titleLbl];

    self.scoreLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.scoreLbl.text = @"SCORE: 0";
    self.scoreLbl.fontColor = [UIColor whiteColor];
    self.scoreLbl.fontSize = 16;
    self.scoreLbl.position = CGPointMake(self.size.width / 2, self.size.height - 40);
    [self.bloomNode addChild:self.scoreLbl];

    CGFloat overlayW = self.size.width - 60;
    CGFloat overlayH = self.size.height - 120;
    self.restartOverlay = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(overlayW, overlayH) cornerRadius:15];
    self.restartOverlay.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    self.restartOverlay.fillColor = [UIColor clearColor]; 
    self.restartOverlay.strokeColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    self.restartOverlay.lineWidth = 4.0;
    self.restartOverlay.zPosition = 50;
    self.restartOverlay.hidden = YES;
    [self.bloomNode addChild:self.restartOverlay];

    self.startBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.startBtn.text = @"▶ START";
    self.startBtn.fontColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    self.startBtn.fontSize = 40;
    self.startBtn.position = CGPointMake(self.size.width / 2, self.size.height / 2 - 15);
    self.startBtn.zPosition = 51; 
    [self.bloomNode addChild:self.startBtn];

    self.pauseBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.pauseBtn.text = @"⏸";
    self.pauseBtn.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    self.pauseBtn.fontSize = 24;
    self.pauseBtn.position = CGPointMake(30, self.size.height - 40); // Aligned with score
    [self.bloomNode addChild:self.pauseBtn];

    self.closeBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.closeBtn.text = @"❌";
    self.closeBtn.fontColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    self.closeBtn.fontSize = 20;
    self.closeBtn.position = CGPointMake(self.size.width - 30, self.size.height - 40); // Aligned with score
    [self.bloomNode addChild:self.closeBtn];
    
    self.highScoreBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.highScoreBtn.text = @"🏆 HIGH SCORES";
    self.highScoreBtn.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    self.highScoreBtn.fontSize = 16;
    self.highScoreBtn.position = CGPointMake(self.size.width / 2, 20); 
    [self.bloomNode addChild:self.highScoreBtn];
}

- (void)setupGestures:(SKView *)view {
    NSArray *dirs = @[@(UISwipeGestureRecognizerDirectionUp), @(UISwipeGestureRecognizerDirectionDown), 
                      @(UISwipeGestureRecognizerDirectionLeft), @(UISwipeGestureRecognizerDirectionRight)];
    for (NSNumber *dir in dirs) {
        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
        swipe.direction = dir.integerValue;
        [view addGestureRecognizer:swipe];
    }
}

- (void)showLeaderboard {
    if (self.leaderboardNode) return;
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    NSInteger best = [def integerForKey:@"ADS_SnakeHighScore"];
    
    self.leaderboardNode = [SKNode node];
    self.leaderboardNode.zPosition = 100;
    self.leaderboardNode.alpha = 0;
    
    // Invisible fullscreen touch blocker guarantees taps are caught
    SKShapeNode *blocker = [SKShapeNode shapeNodeWithRectOfSize:self.size];
    blocker.position = CGPointMake(self.size.width/2, self.size.height/2);
    blocker.fillColor = [UIColor clearColor];
    blocker.strokeColor = [UIColor clearColor];
    [self.leaderboardNode addChild:blocker];
    
    SKShapeNode *bg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(220, 140) cornerRadius:12];
    bg.fillColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    bg.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    bg.lineWidth = 2.0;
    bg.position = CGPointMake(self.size.width/2, self.size.height/2);
    [self.leaderboardNode addChild:bg];
    
    SKLabelNode *title = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    title.text = @"HIGH SCORE";
    title.fontColor = [UIColor whiteColor];
    title.fontSize = 22;
    title.position = CGPointMake(0, 25);
    [bg addChild:title];
    
    SKLabelNode *val = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    val.text = [NSString stringWithFormat:@"%ld", (long)best];
    val.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    val.fontSize = 36;
    val.position = CGPointMake(0, -15);
    [bg addChild:val];
    
    SKLabelNode *tap = [SKLabelNode labelNodeWithFontNamed:@"Courier"];
    tap.text = @"Tap anywhere to close";
    tap.fontColor = [UIColor grayColor];
    tap.fontSize = 12;
    tap.position = CGPointMake(0, -50);
    [bg addChild:tap];
    
    [self.bloomNode addChild:self.leaderboardNode];
    [self.leaderboardNode runAction:[SKAction fadeInWithDuration:0.2]];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint loc = [touch locationInNode:self];

    if (self.leaderboardNode) {
        SKNode *node = self.leaderboardNode;
        self.leaderboardNode = nil; // Immediate nil = no tap glitches
        [node runAction:[SKAction sequence:@[
            [SKAction fadeOutWithDuration:0.2],
            [SKAction removeFromParent]
        ]]];
        return;
    }

    if ([self.closeBtn containsPoint:loc]) {
        if (self.exitHandler) self.exitHandler();
        return;
    }
    
    if (!self.highScoreBtn.hidden && [self.highScoreBtn containsPoint:loc]) {
        [self showLeaderboard];
        return;
    }

    if (self.gameState == ADSGameStateMenu) {
        [self resetGame];
    } else if (self.gameState == ADSGameStateDead) {
        if ([self.startBtn containsPoint:loc] || (!self.restartOverlay.hidden && [self.restartOverlay containsPoint:loc])) {
            [self resetGame];
        }
    } else if (self.gameState == ADSGameStatePlaying) {
        if ([self.pauseBtn containsPoint:loc]) {
            self.gameState = ADSGameStatePaused;
            self.startBtn.text = @"▶ RESUME";
            self.startBtn.hidden = NO;
        }
    } else if (self.gameState == ADSGameStatePaused) {
        if ([self.startBtn containsPoint:loc]) {
            self.gameState = ADSGameStatePlaying;
            self.startBtn.hidden = YES;
        }
    }
}

- (void)handleSwipe:(UISwipeGestureRecognizer *)sender {
    if (self.gameState != ADSGameStatePlaying) return;
    
    if (sender.direction == UISwipeGestureRecognizerDirectionUp && self.direction.dy == 0) self.direction = CGVectorMake(0, 1);
    else if (sender.direction == UISwipeGestureRecognizerDirectionDown && self.direction.dy == 0) self.direction = CGVectorMake(0, -1);
    else if (sender.direction == UISwipeGestureRecognizerDirectionLeft && self.direction.dx == 0) self.direction = CGVectorMake(-1, 0);
    else if (sender.direction == UISwipeGestureRecognizerDirectionRight && self.direction.dx == 0) self.direction = CGVectorMake(1, 0);
}

- (void)drawWalls {
    CGFloat w = ([self maxX] - [self minX] + 1) * kGridSize;
    CGFloat h = ([self maxY] - [self minY] + 1) * kGridSize;
    SKShapeNode *border = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(w, h)];
    border.position = CGPointMake(([self minX] + [self maxX])/2.0 * kGridSize, ([self minY] + [self maxY])/2.0 * kGridSize);
    border.strokeColor = [UIColor colorWithRed:0.2 green:0.2 blue:1.0 alpha:1.0];
    border.lineWidth = 4.0;
    [self.bloomNode addChild:border];
}

- (void)resetGame {
    self.gameState = ADSGameStatePlaying;
    self.startBtn.hidden = YES;
    self.restartOverlay.hidden = YES;
    self.highScoreBtn.hidden = YES; // Hide high score during gameplay
    self.score = 0;
    self.scoreLbl.text = @"SCORE: 0";
    self.direction = CGVectorMake(1, 0);
    self.snake = [NSMutableArray arrayWithObject:[NSValue valueWithCGPoint:CGPointMake([self minX]+2, [self minY]+2)]];
    [self spawnFood];
    self.lastTick = 0;
}

- (void)spawnFood {
    BOOL valid = NO;
    int x = 0, y = 0;
    
    while (!valid) {
        x = [self minX] + arc4random_uniform([self maxX] - [self minX] + 1);
        y = [self minY] + arc4random_uniform([self maxY] - [self minY] + 1);
        valid = YES;
        
        CGPoint testPoint = CGPointMake(x, y);
        for (NSValue *val in self.snake) {
            if (CGPointEqualToPoint(val.CGPointValue, testPoint)) {
                valid = NO;
                break;
            }
        }
    }
    
    self.food = CGPointMake(x, y);
}

- (void)update:(NSTimeInterval)currentTime {
    if (self.gameState != ADSGameStatePlaying) return;
    if (currentTime - self.lastTick < 0.22) return;
    self.lastTick = currentTime;
    
    CGPoint head = self.snake.firstObject.CGPointValue;
    CGPoint next = CGPointMake(head.x + self.direction.dx, head.y + self.direction.dy);
    
    if (next.x < [self minX] || next.x > [self maxX] || next.y < [self minY] || next.y > [self maxY]) { [self die]; return; }
    
    for (NSValue *val in self.snake) {
        if (CGPointEqualToPoint(val.CGPointValue, next)) { [self die]; return; }
    }
    
    [self.snake insertObject:[NSValue valueWithCGPoint:next] atIndex:0];
    
    if (CGPointEqualToPoint(next, self.food)) {
        self.score += 10;
        self.scoreLbl.text = [NSString stringWithFormat:@"SCORE: %ld", (long)self.score];
        
        // Haptic feedback updated to Rigid
        UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
        [feed impactOccurred];
        
        [self spawnFood];
    } else {
        [self.snake removeLastObject];
    }
    [self render];
}

- (void)die {
    self.gameState = ADSGameStateDead;
    self.startBtn.text = @"↻ RESTART";
    self.startBtn.hidden = NO;
    self.restartOverlay.hidden = NO;
    self.highScoreBtn.hidden = NO; // Reveal high score when game ends
    
    UINotificationFeedbackGenerator *feed = [[UINotificationFeedbackGenerator alloc] init];
    [feed notificationOccurred:UINotificationFeedbackTypeWarning];
    
    SKShapeNode *flash = [SKShapeNode shapeNodeWithRectOfSize:self.size];
    flash.position = CGPointMake(self.size.width/2, self.size.height/2);
    flash.fillColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.5];
    [self addChild:flash];
    [flash runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.3], [SKAction removeFromParent]]]];
    
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    NSInteger best = [def integerForKey:@"ADS_SnakeHighScore"];
    if (self.score > best) {
        [def setInteger:self.score forKey:@"ADS_SnakeHighScore"];
        [def synchronize];
        [self showLeaderboard];
    }
}

- (void)render {
    [self.gameLayer removeAllChildren];
    
    SKShapeNode *fNode = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(kGridSize-2, kGridSize-2)];
    fNode.fillColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    fNode.position = CGPointMake(self.food.x * kGridSize, self.food.y * kGridSize);
    
    SKAction *pulseUp = [SKAction scaleTo:1.2 duration:0.3];
    SKAction *pulseDown = [SKAction scaleTo:0.8 duration:0.3];
    [fNode runAction:[SKAction repeatActionForever:[SKAction sequence:@[pulseUp, pulseDown]]]];
    
    [self.gameLayer addChild:fNode];
    
    for (NSValue *val in self.snake) {
        CGPoint p = val.CGPointValue;
        SKShapeNode *sNode = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(kGridSize-2, kGridSize-2)];
        sNode.fillColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
        sNode.position = CGPointMake(p.x * kGridSize, p.y * kGridSize);
        [self.gameLayer addChild:sNode];
    }
}
@end

// --- ROP STACKER (TETRIS) SCENE ---
@implementation ADSROPStackerScene {
    NSMutableDictionary *_board; 
    int _bX, _bY, _bType, _bRot;
    NSTimeInterval _lastTick, _tickRate;
    NSInteger _score;
    SKNode *_gameLayer;
    SKNode *_leaderboardNode;
    
    SKLabelNode *_scoreLbl;
    SKLabelNode *_highScoreBtn;
    SKLabelNode *_startBtn;
    SKLabelNode *_pauseBtn;
    SKLabelNode *_closeBtn;
    SKShapeNode *_restartOverlay;
    
    BOOL _isDead, _isPlaying, _isPaused;
}

// Increased grid size to make the playing area take up maximum room
static const CGFloat kRopGrid = 17.0; 
static const int kRopCols = 10;
static const int kRopRows = 20;

// Hardcoded 4-state rotations to prevent "shimmying"
static int rop_blocks[7][4][4][2] = {
    // 0: I - Toggles perfectly horizontal/vertical around a fixed center
    { {{-1,0}, {0,0}, {1,0}, {2,0}}, {{0,1}, {0,0}, {0,-1}, {0,-2}}, {{-1,0}, {0,0}, {1,0}, {2,0}}, {{0,1}, {0,0}, {0,-1}, {0,-2}} },
    // 1: J
    { {{-1,1}, {-1,0}, {0,0}, {1,0}}, {{1,1}, {0,1}, {0,0}, {0,-1}}, {{1,-1}, {1,0}, {0,0}, {-1,0}}, {{-1,-1}, {0,-1}, {0,0}, {0,1}} },
    // 2: L
    { {{1,1}, {-1,0}, {0,0}, {1,0}}, {{1,-1}, {0,1}, {0,0}, {0,-1}}, {{-1,-1}, {1,0}, {0,0}, {-1,0}}, {{-1,1}, {0,-1}, {0,0}, {0,1}} },
    // 3: O - Doesn't rotate
    { {{0,1}, {1,1}, {0,0}, {1,0}}, {{0,1}, {1,1}, {0,0}, {1,0}}, {{0,1}, {1,1}, {0,0}, {1,0}}, {{0,1}, {1,1}, {0,0}, {1,0}} },
    // 4: S
    { {{0,1}, {1,1}, {-1,0}, {0,0}}, {{0,1}, {0,0}, {1,0}, {1,-1}}, {{0,1}, {1,1}, {-1,0}, {0,0}}, {{0,1}, {0,0}, {1,0}, {1,-1}} },
    // 5: T
    { {{0,1}, {-1,0}, {0,0}, {1,0}}, {{0,1}, {0,0}, {1,0}, {0,-1}}, {{-1,0}, {0,0}, {1,0}, {0,-1}}, {{0,1}, {-1,0}, {0,0}, {0,-1}} },
    // 6: Z
    { {{-1,1}, {0,1}, {0,0}, {1,0}}, {{1,1}, {1,0}, {0,0}, {0,-1}}, {{-1,1}, {0,1}, {0,0}, {1,0}}, {{1,1}, {1,0}, {0,0}, {0,-1}} }
};

- (void)didMoveToView:(SKView *)view {
    self.backgroundColor = [UIColor blackColor];
    _board = [NSMutableDictionary dictionary];
    _tickRate = 0.5;
    
    _gameLayer = [SKNode node];
    
    CGFloat boardWidth = kRopCols * kRopGrid;
    CGFloat boardHeight = kRopRows * kRopGrid;
    // Push the board down slightly to maximize space while leaving room for top UI
    _gameLayer.position = CGPointMake((self.size.width - boardWidth)/2.0, (self.size.height - boardHeight)/2.0 - 5);
    [self addChild:_gameLayer];
    
    [self setupUI];
    [self setupGestures:view];
}

- (void)setupUI {
    // Score Label (Centered bottom)
    _scoreLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _scoreLbl.text = @"STACKS CLEARED: 0";
    _scoreLbl.fontSize = 14;
    _scoreLbl.fontColor = [UIColor whiteColor];
    _scoreLbl.position = CGPointMake(self.size.width / 2, 8);
    [self addChild:_scoreLbl];

    // Pause Button (Top Left)
    _pauseBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _pauseBtn.text = @"⏸";
    _pauseBtn.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _pauseBtn.fontSize = 22;
    _pauseBtn.position = CGPointMake(25, self.size.height - 25);
    [self addChild:_pauseBtn];

    // Close Button (Top Right)
    _closeBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _closeBtn.text = @"❌";
    _closeBtn.fontColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    _closeBtn.fontSize = 20;
    _closeBtn.position = CGPointMake(self.size.width - 25, self.size.height - 25);
    [self addChild:_closeBtn];
    
    // High Score Button (Top Center)
    _highScoreBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _highScoreBtn.text = @"🏆 HIGH SCORES";
    _highScoreBtn.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _highScoreBtn.fontSize = 14;
    _highScoreBtn.position = CGPointMake(self.size.width / 2, self.size.height - 25);
    [self addChild:_highScoreBtn];

    // Large Restart Overlay (matches Exploit Eater but golden theme)
    CGFloat overlayW = self.size.width - 60;
    CGFloat overlayH = self.size.height - 120;
    _restartOverlay = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(overlayW, overlayH) cornerRadius:15];
    _restartOverlay.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    _restartOverlay.fillColor = [UIColor colorWithWhite:0.0 alpha:0.8]; 
    _restartOverlay.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _restartOverlay.lineWidth = 4.0;
    _restartOverlay.zPosition = 50;
    _restartOverlay.hidden = YES;
    [self addChild:_restartOverlay];

    // Start / Retry / Resume Button
    _startBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _startBtn.text = @"▶ INJECT PAYLOAD";
    _startBtn.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _startBtn.fontSize = 22;
    _startBtn.position = CGPointMake(self.size.width / 2, self.size.height / 2 - 8);
    _startBtn.zPosition = 51;
    [self addChild:_startBtn];
}

- (void)setupGestures:(SKView *)view {
    NSArray *dirs = @[@(UISwipeGestureRecognizerDirectionDown), @(UISwipeGestureRecognizerDirectionLeft), @(UISwipeGestureRecognizerDirectionRight)];
    for (NSNumber *dir in dirs) {
        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
        swipe.direction = dir.integerValue;
        [view addGestureRecognizer:swipe];
    }
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [view addGestureRecognizer:tap];
}

- (void)showLeaderboard {
    if (_leaderboardNode) return;
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    NSInteger best = [def integerForKey:@"ADS_ROPHighScore"];
    
    _leaderboardNode = [SKNode node];
    _leaderboardNode.zPosition = 100;
    _leaderboardNode.alpha = 0;
    
    SKShapeNode *blocker = [SKShapeNode shapeNodeWithRectOfSize:self.size];
    blocker.position = CGPointMake(self.size.width/2, self.size.height/2);
    blocker.fillColor = [UIColor clearColor];
    blocker.strokeColor = [UIColor clearColor];
    [_leaderboardNode addChild:blocker];
    
    SKShapeNode *bg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(220, 140) cornerRadius:12];
    bg.fillColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    bg.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    bg.lineWidth = 2.0;
    bg.position = CGPointMake(self.size.width/2, self.size.height/2);
    [_leaderboardNode addChild:bg];
    
    SKLabelNode *title = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    title.text = @"HIGH SCORE";
    title.fontColor = [UIColor whiteColor];
    title.fontSize = 22;
    title.position = CGPointMake(0, 25);
    [bg addChild:title];
    
    SKLabelNode *val = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    val.text = [NSString stringWithFormat:@"%ld", (long)best];
    val.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    val.fontSize = 36;
    val.position = CGPointMake(0, -15);
    [bg addChild:val];
    
    SKLabelNode *tap = [SKLabelNode labelNodeWithFontNamed:@"Courier"];
    tap.text = @"Tap anywhere to close";
    tap.fontColor = [UIColor grayColor];
    tap.fontSize = 12;
    tap.position = CGPointMake(0, -50);
    [bg addChild:tap];
    
    [self addChild:_leaderboardNode];
    [_leaderboardNode runAction:[SKAction fadeInWithDuration:0.2]];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint loc = [[touches anyObject] locationInNode:self];
    
    if (_leaderboardNode) {
        SKNode *node = _leaderboardNode;
        _leaderboardNode = nil;
        [node runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.2], [SKAction removeFromParent]]]];
        return;
    }

    if ([_closeBtn containsPoint:loc]) {
        if (self.exitHandler) self.exitHandler();
        return;
    }
    
    if (!_highScoreBtn.hidden && [_highScoreBtn containsPoint:loc]) {
        [self showLeaderboard];
        return;
    }

    if (!_isPlaying || _isDead) {
        if ([_startBtn containsPoint:loc] || (!_restartOverlay.hidden && [_restartOverlay containsPoint:loc])) {
            [self resetGame];
        }
    } else if (_isPlaying && !_isDead) {
        if ([_pauseBtn containsPoint:loc]) {
            _isPaused = !_isPaused;
            if (_isPaused) {
                _startBtn.text = @"▶ RESUME";
                _startBtn.hidden = NO;
                _restartOverlay.hidden = NO;
            } else {
                _startBtn.hidden = YES;
                _restartOverlay.hidden = YES;
            }
        }
    }
}

- (void)handleSwipe:(UISwipeGestureRecognizer *)sender {
    if (!_isPlaying || _isDead || _isPaused) return;
    if (sender.direction == UISwipeGestureRecognizerDirectionLeft && [self isValidX:_bX-1 y:_bY rot:_bRot type:_bType]) _bX--;
    if (sender.direction == UISwipeGestureRecognizerDirectionRight && [self isValidX:_bX+1 y:_bY rot:_bRot type:_bType]) _bX++;
    if (sender.direction == UISwipeGestureRecognizerDirectionDown) {
        while ([self isValidX:_bX y:_bY-1 rot:_bRot type:_bType]) _bY--;
        _lastTick = 0; 
    }
    [self render];
}

- (void)handleTap:(UITapGestureRecognizer *)sender {
    if (!_isPlaying || _isDead || _isPaused) return;
    if (_bType == 3) return; // O block doesn't rotate
    int nextRot = (_bRot + 1) % 4;
    if ([self isValidX:_bX y:_bY rot:nextRot type:_bType]) _bRot = nextRot;
    [self render];
}

- (void)resetGame {
    _isPlaying = YES;
    _isDead = NO;
    _isPaused = NO;
    _startBtn.hidden = YES;
    _restartOverlay.hidden = YES;
    _highScoreBtn.hidden = YES;
    [_board removeAllObjects];
    _score = 0;
    _tickRate = 0.5;
    _scoreLbl.text = @"STACKS CLEARED: 0";
    [self spawnBlock];
}

- (void)die {
    _isDead = YES;
    _isPlaying = NO;
    _startBtn.text = @"↻ KERNEL PANIC";
    _startBtn.hidden = NO;
    _restartOverlay.hidden = NO;
    _highScoreBtn.hidden = NO;
    
    UINotificationFeedbackGenerator *feed = [[UINotificationFeedbackGenerator alloc] init];
    [feed notificationOccurred:UINotificationFeedbackTypeError];
    
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    NSInteger best = [def integerForKey:@"ADS_ROPHighScore"];
    if (_score > best) {
        [def setInteger:_score forKey:@"ADS_ROPHighScore"];
        [def synchronize];
        [self showLeaderboard];
    }
}

- (void)spawnBlock {
    _bType = arc4random_uniform(7);
    _bRot = 0;
    _bX = kRopCols / 2;
    _bY = kRopRows - 2;
    
    // Death Condition: If the space we are spawning into is already blocked, game over.
    if (![self isValidX:_bX y:_bY rot:_bRot type:_bType]) {
        [self die];
    }
}

- (BOOL)isValidX:(int)x y:(int)y rot:(int)rot type:(int)type {
    for (int i=0; i<4; i++) {
        int nx = x + rop_blocks[type][rot][i][0];
        int ny = y + rop_blocks[type][rot][i][1];
        if (nx < 0 || nx >= kRopCols || ny < 0 || ny >= kRopRows) return NO;
        if (_board[[NSString stringWithFormat:@"%d,%d", nx, ny]] != nil) return NO;
    }
    return YES;
}

- (void)update:(NSTimeInterval)currentTime {
    if (!_isPlaying || _isDead || _isPaused) return;
    if (currentTime - _lastTick < _tickRate) return;
    _lastTick = currentTime;
    
    if ([self isValidX:_bX y:_bY-1 rot:_bRot type:_bType]) {
        _bY--;
    } else {
        [self lockBlock];
        [self clearLines];
        if (!_isDead) [self spawnBlock];
    }
    [self render];
}

- (UIColor *)colorForType:(int)type {
    NSArray *colors = @[[UIColor cyanColor], [UIColor blueColor], [UIColor orangeColor], [UIColor yellowColor], [UIColor greenColor], [UIColor purpleColor], [UIColor redColor]];
    return colors[type];
}

- (void)lockBlock {
    UIColor *c = [self colorForType:_bType];
    for (int i=0; i<4; i++) {
        int nx = _bX + rop_blocks[_bType][_bRot][i][0];
        int ny = _bY + rop_blocks[_bType][_bRot][i][1];
        _board[[NSString stringWithFormat:@"%d,%d", nx, ny]] = c;
    }
    UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feed impactOccurred];
}

- (void)clearLines {
    int linesCleared = 0;
    for (int y = 0; y < kRopRows; y++) {
        BOOL full = YES;
        for (int x = 0; x < kRopCols; x++) {
            if (!_board[[NSString stringWithFormat:@"%d,%d", x, y]]) { full = NO; break; }
        }
        if (full) {
            linesCleared++;
            for (int dropY = y; dropY < kRopRows - 1; dropY++) {
                for (int x = 0; x < kRopCols; x++) {
                    UIColor *above = _board[[NSString stringWithFormat:@"%d,%d", x, dropY+1]];
                    if (above) _board[[NSString stringWithFormat:@"%d,%d", x, dropY]] = above;
                    else [_board removeObjectForKey:[NSString stringWithFormat:@"%d,%d", x, dropY]];
                }
            }
            y--; 
        }
    }
    
    if (linesCleared > 0) {
        _score += linesCleared;
        _scoreLbl.text = [NSString stringWithFormat:@"STACKS CLEARED: %ld", (long)_score];
        _tickRate = MAX(0.1, 0.5 - (_score * 0.02)); 
        
        // --- 4 ROW CELEBRATION ANIMATION ---
        if (linesCleared == 4) {
            SKLabelNode *msg = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
            msg.text = @"ROP CHAIN SECURED!";
            msg.fontColor = [UIColor magentaColor];
            msg.fontSize = 24;
            msg.position = CGPointMake(self.size.width/2, self.size.height/2);
            msg.zPosition = 100;
            [self addChild:msg];
            
            SKAction *moveUp = [SKAction moveByX:0 y:40 duration:0.8];
            SKAction *fadeOut = [SKAction fadeOutWithDuration:0.8];
            [msg runAction:[SKAction sequence:@[[SKAction group:@[moveUp, fadeOut]], [SKAction removeFromParent]]]];
            
            SKShapeNode *flash = [SKShapeNode shapeNodeWithRectOfSize:self.size];
            flash.position = CGPointMake(self.size.width/2, self.size.height/2);
            flash.fillColor = [UIColor whiteColor];
            flash.alpha = 0.7;
            flash.zPosition = 99;
            [self addChild:flash];
            [flash runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.3], [SKAction removeFromParent]]]];
            
            UINotificationFeedbackGenerator *successFeed = [[UINotificationFeedbackGenerator alloc] init];
            [successFeed notificationOccurred:UINotificationFeedbackTypeSuccess];
        }
    }
}

- (void)render {
    [_gameLayer removeAllChildren];
    SKShapeNode *border = [SKShapeNode shapeNodeWithRect:CGRectMake(0, 0, kRopCols * kRopGrid, kRopRows * kRopGrid)];
    border.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    border.lineWidth = 2.0;
    [_gameLayer addChild:border];
    
    // Draw locked blocks
    for (NSString *key in _board) {
        NSArray *comps = [key componentsSeparatedByString:@","];
        int x = [comps[0] intValue], y = [comps[1] intValue];
        SKShapeNode *node = [SKShapeNode shapeNodeWithRect:CGRectMake(x*kRopGrid, y*kRopGrid, kRopGrid-1, kRopGrid-1)];
        node.fillColor = _board[key];
        node.lineWidth = 0;
        [_gameLayer addChild:node];
    }
    
    // Draw current block
    if (_isPlaying && !_isDead) {
        UIColor *c = [self colorForType:_bType];
        for (int i=0; i<4; i++) {
            int nx = _bX + rop_blocks[_bType][_bRot][i][0];
            int ny = _bY + rop_blocks[_bType][_bRot][i][1];
            SKShapeNode *node = [SKShapeNode shapeNodeWithRect:CGRectMake(nx*kRopGrid, ny*kRopGrid, kRopGrid-1, kRopGrid-1)];
            node.fillColor = c;
            node.lineWidth = 0;
            [_gameLayer addChild:node];
        }
    }
}
@end

// --- MENU SCENE ---
@implementation ADSGameMenuScene {
    SKLabelNode *_closeBtn;
    SKShapeNode *_btnSnake;
    SKShapeNode *_btnTetris;
}

- (void)didMoveToView:(SKView *)view {
    self.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    
    SKLabelNode *title = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    title.text = @"SELECT TARGET PAYLOAD";
    title.fontColor = [UIColor whiteColor];
    title.fontSize = 22;
    title.position = CGPointMake(self.size.width/2, self.size.height - 60);
    [self addChild:title];
    
    _closeBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _closeBtn.text = @"❌";
    _closeBtn.fontSize = 20;
    _closeBtn.position = CGPointMake(self.size.width - 30, self.size.height - 40);
    [self addChild:_closeBtn];

    // Exploit Eater Button
    _btnSnake = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(200, 80) cornerRadius:12];
    _btnSnake.position = CGPointMake(self.size.width/2, self.size.height/2 + 50);
    _btnSnake.fillColor = [UIColor clearColor];
    _btnSnake.strokeColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    _btnSnake.lineWidth = 3.0;
    [self addChild:_btnSnake];
    
    SKLabelNode *snakeLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    snakeLbl.text = @"🐍 EXPLOIT EATER";
    snakeLbl.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    snakeLbl.fontSize = 18;
    snakeLbl.position = CGPointMake(0, -6);
    [_btnSnake addChild:snakeLbl];

    // ROP Stacker Button
    _btnTetris = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(200, 80) cornerRadius:12];
    _btnTetris.position = CGPointMake(self.size.width/2, self.size.height/2 - 50);
    _btnTetris.fillColor = [UIColor clearColor];
    _btnTetris.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _btnTetris.lineWidth = 3.0;
    [self addChild:_btnTetris];
    
    SKLabelNode *tetrisLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    tetrisLbl.text = @"🧱 ROP STACKER";
    tetrisLbl.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    tetrisLbl.fontSize = 18;
    tetrisLbl.position = CGPointMake(0, -6);
    [_btnTetris addChild:tetrisLbl];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint loc = [[touches anyObject] locationInNode:self];
    
    if ([_closeBtn containsPoint:loc]) {
        if (self.exitHandler) self.exitHandler();
        return;
    }
    
    if ([_btnSnake containsPoint:loc]) {
        if (self.onSelectGame) self.onSelectGame(0);
    } else if ([_btnTetris containsPoint:loc]) {
        if (self.onSelectGame) self.onSelectGame(1);
    }
}
@end

// --- CONTROLLER INTEGRATION ---
@interface AntiDarkSwordCreditsController ()
@property (nonatomic, strong) SKView *gameView;
@end

@implementation AntiDarkSwordCreditsController

- (BOOL)canBecomeFirstResponder { return YES; }

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self resignFirstResponder];
    [self teardownGame];
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) {
        if (!self.gameView) [self launchGame]; 
    }
}

- (void)launchGame {
    if (self.gameView) return;
    
    UITableView *table = (UITableView *)[self valueForKey:@"_table"];
    if (!table) return;

    CGFloat width = table.bounds.size.width;
    CGFloat height = 350.0;
    
    UIView *footerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height + 40)];
    footerContainer.backgroundColor = [UIColor clearColor];
    
    self.gameView = [[SKView alloc] initWithFrame:CGRectMake(16, 20, width - 32, height)];
    self.gameView.layer.cornerRadius = 12.0;
    self.gameView.clipsToBounds = YES;
    self.gameView.alpha = 0.0;
    
    [footerContainer addSubview:self.gameView];
    table.tableFooterView = footerContainer;
    
    ADSGameMenuScene *menuScene = [[ADSGameMenuScene alloc] initWithSize:self.gameView.bounds.size];
    menuScene.scaleMode = SKSceneScaleModeAspectFill;
    
    __weak typeof(self) weakSelf = self;
    menuScene.exitHandler = ^{ [weakSelf teardownGame]; };
    
    menuScene.onSelectGame = ^(NSInteger gameIndex) {
        SKScene *selectedScene;
        if (gameIndex == 0) {
            ADSExploitEaterScene *s = [[ADSExploitEaterScene alloc] initWithSize:weakSelf.gameView.bounds.size];
            s.exitHandler = ^{ [weakSelf teardownGame]; };
            selectedScene = s;
        } else {
            ADSROPStackerScene *s = [[ADSROPStackerScene alloc] initWithSize:weakSelf.gameView.bounds.size];
            s.exitHandler = ^{ [weakSelf teardownGame]; };
            selectedScene = s;
        }
        selectedScene.scaleMode = SKSceneScaleModeAspectFill;
        SKTransition *transition = [SKTransition pushWithDirection:SKTransitionDirectionLeft duration:0.3];
        [weakSelf.gameView presentScene:selectedScene transition:transition];
    };
    
    [self.gameView presentScene:menuScene];
    
    [UIView animateWithDuration:0.5 animations:^{
        self.gameView.alpha = 1.0;
    } completion:^(BOOL finished) {
        CGRect footerRect = [table convertRect:table.tableFooterView.bounds fromView:table.tableFooterView];
        [table scrollRectToVisible:footerRect animated:YES];
        table.scrollEnabled = NO;
    }];
}

- (void)teardownGame {
    if (!self.gameView) return;
    
    UITableView *table = (UITableView *)[self valueForKey:@"_table"];
    if (table) table.scrollEnabled = YES;

    [UIView animateWithDuration:0.5 animations:^{
        self.gameView.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self.gameView presentScene:nil];
        [self.gameView removeFromSuperview];
        self.gameView = nil;
        if (table) table.tableFooterView = nil;
    }];
}

- (UIImage *)resizeIcon:(UIImage *)image toSize:(CGSize)size {
    if (!image) return nil;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
}
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        CGSize iconSize = CGSizeMake(29, 29);
        
        PSSpecifier *group = [PSSpecifier preferenceSpecifierNamed:@"Contributors" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [specs addObject:group];
        
        PSSpecifier *eoln = [PSSpecifier preferenceSpecifierNamed:@"EolnMsuk (AntiDarkSword)" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        eoln->action = @selector(openDevLink);
        UIImage *rawEoln = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"eoln" ofType:@"png"]];
        if (rawEoln) [eoln setProperty:[self resizeIcon:rawEoln toSize:iconSize] forKey:@"iconImage"];
        [specs addObject:eoln];
        
        PSSpecifier *ghh = [PSSpecifier preferenceSpecifierNamed:@"ghh-jb (CorelliumDecoy)" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        ghh->action = @selector(openDev2Link);
        UIImage *rawGhh = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"ghh-jb" ofType:@"png"]];
        if (rawGhh) [ghh setProperty:[self resizeIcon:rawGhh toSize:iconSize] forKey:@"iconImage"];
        [specs addObject:ghh];
        
        _specifiers = [specs copy];
    }
    return _specifiers;
}
- (void)openDevLink {
    NSURL *url = [NSURL URLWithString:@"https://github.com/EolnMsuk/"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}
- (void)openDev2Link {
    NSURL *url = [NSURL URLWithString:@"https://github.com/ghh-jb"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}
@end

@interface AntiDarkSwordAppController : PSListController
@property (nonatomic, strong) NSString *targetID;
@property (nonatomic, assign) NSInteger ruleType;
+ (BOOL)isDaemonTarget:(NSString *)targetID;
+ (BOOL)isApplicableFeature:(NSString *)featureKey forTarget:(NSString *)targetID;
- (BOOL)isGlobalOverrideActiveForFeature:(NSString *)featureKey;
@end

@interface AntiDarkSwordDaemonListController : PSListController
@end

static NSDictionary *ads_daemon_alias_map(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"imagent":             @"com.apple.imagent",
            @"IMDPersistenceAgent": @"com.apple.IMDPersistenceAgent",
            @"apsd":                @"com.apple.apsd",
            @"identityservicesd":   @"com.apple.identityservicesd"
        };
    });
    return map;
}

static void ProbeCounterNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    AntiDarkSwordDaemonListController *controller = (__bridge AntiDarkSwordDaemonListController *)observer;
    if (controller) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [controller reloadSpecifiers];
        });
    }
}

@implementation AntiDarkSwordDaemonListController

- (void)viewDidLoad {
    [super viewDidLoad];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (CFNotificationCallback)ProbeCounterNotification, CFSTR("com.eolnmsuk.antidarkswordprefs/counter"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), CFSTR("com.eolnmsuk.antidarkswordprefs/counter"), NULL);
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];
        NSUserDefaults *defaults = ads_defaults();
        BOOL corelliumEnabled = [defaults boolForKey:@"corelliumDecoyEnabled"];
        NSInteger autoProtectLevel = [defaults integerForKey:@"autoProtectLevel"] ?: 1;

        PSSpecifier *decoyGroup = [PSSpecifier preferenceSpecifierNamed:@"Corellium Honeypot" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [decoyGroup setProperty:@"Spoofs Corellium environment to cause exploits (like Coruna) to self-abort." forKey:@"footerText"];
        [specs addObject:decoyGroup];

        PSSpecifier *decoySpec = [PSSpecifier preferenceSpecifierNamed:@"Enable Corellium Honeypot" target:self set:@selector(setCorelliumEnabled:specifier:) get:@selector(getCorelliumEnabled:) detail:nil cell:PSSwitchCell edit:nil];
        [specs addObject:decoySpec];

        BOOL showCounter = [defaults boolForKey:@"countersEnabled"];
        NSInteger probeCount = [defaults integerForKey:@"corelliumProbeCount"];

        PSSpecifier *counterGroup = [PSSpecifier preferenceSpecifierNamed:@"Attack Statistics" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [counterGroup setProperty:@"Counts Corellium environment probe attempts detected by system daemons." forKey:@"footerText"];
        [specs addObject:counterGroup];

        PSSpecifier *counterToggle = [PSSpecifier preferenceSpecifierNamed:@"Enable Attack Counter" target:self set:@selector(setCountersEnabled:specifier:) get:@selector(getCountersEnabled:) detail:nil cell:PSSwitchCell edit:nil];
        if (!corelliumEnabled) [counterToggle setProperty:@NO forKey:@"enabled"];
        [specs addObject:counterToggle];

        if (showCounter && corelliumEnabled) {
            NSString *countLabel = (probeCount == 0) ? @"Corellium Probes Detected: None" : [NSString stringWithFormat:@"Corellium Probes Detected: %ld", (long)probeCount];
            PSSpecifier *countCell = [PSSpecifier preferenceSpecifierNamed:countLabel target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
            [specs addObject:countCell];

            PSSpecifier *resetBtn = [PSSpecifier preferenceSpecifierNamed:@"Reset Counter" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            resetBtn->action = @selector(resetProbeCounter);
            [specs addObject:resetBtn];
        }

        PSSpecifier *group = [PSSpecifier preferenceSpecifierNamed:@"System Daemons" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [group setProperty:@"Restricting a daemon bypasses all zero-click mitigations for that process." forKey:@"footerText"];
        [specs addObject:group];

        NSArray *daemons = @[@"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"];
        for (NSString *daemon in daemons) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:[rootCtrl displayNameForTargetID:daemon] target:self set:@selector(setDaemonEnabled:specifier:) get:@selector(getDaemonEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [spec setProperty:daemon forKey:@"targetID"];
            if (corelliumEnabled) [spec setProperty:@NO forKey:@"enabled"];
            [specs addObject:spec];
        }

        PSSpecifier *globalGroup = [PSSpecifier preferenceSpecifierNamed:@"⚠︎  Global Rules (BETA) ⚠︎ " target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [globalGroup setProperty:@"Global rules can break almost anything, for advanced users only." forKey:@"footerText"];
        [specs addObject:globalGroup];

        NSArray *globals = @[
            @{@"key": @"globalUASpoofingEnabled", @"label": @"Spoof User Agent"},
            @{@"key": @"globalDisableJIT", @"label": @"Disable JIT (iOS 16+)"},
            @{@"key": @"globalDisableJIT15", @"label": @"Disable JIT (Legacy)"},
            @{@"key": @"globalDisableJS", @"label": @"Disable JavaScript ⚠︎"},
            @{@"key": @"globalDisableRTC", @"label": @"Disable WebGL & WebRTC"},
            @{@"key": @"globalDisableMedia", @"label": @"Disable Media Auto-Play"},
            @{@"key": @"globalDisableIMessageDL", @"label": @"Disable Msg Auto-Download"},
            @{@"key": @"globalDisableFileAccess", @"label": @"Disable Local File Access"}
        ];

        BOOL isIOS16 = ads_is_ios16();
        BOOL globalJSEnabled = [defaults boolForKey:@"globalDisableJS"];

        for (NSDictionary *g in globals) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:g[@"label"] target:self set:@selector(setGlobalMitigation:specifier:) get:@selector(getGlobalMitigation:) detail:nil cell:PSSwitchCell edit:nil];
            [spec setProperty:g[@"key"] forKey:@"key"];
            if (autoProtectLevel < 3) {
                [spec setProperty:@NO forKey:@"enabled"];
            } else {
                if ([g[@"key"] isEqualToString:@"globalDisableJIT"] && (!isIOS16 || globalJSEnabled)) [spec setProperty:@NO forKey:@"enabled"];
                if ([g[@"key"] isEqualToString:@"globalDisableJIT15"] && (isIOS16 || globalJSEnabled)) [spec setProperty:@NO forKey:@"enabled"];
            }
            [specs addObject:spec];
        }

        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (void)reloadSpecifiers {
    self->_specifiers = nil;
    [super reloadSpecifiers];
}

- (id)getDaemonEnabled:(PSSpecifier *)spec {
    return @(![[ads_defaults() arrayForKey:@"disabledPresetRules"] ?: @[] containsObject:[spec propertyForKey:@"targetID"]]);
}

- (void)setDaemonEnabled:(id)value specifier:(PSSpecifier *)spec {
    NSUserDefaults *defaults = ads_defaults();
    NSMutableArray *disabled = [[defaults arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
    NSString *targetID = [spec propertyForKey:@"targetID"];
    NSDictionary *aliasMap = ads_daemon_alias_map();

    if ([value boolValue]) {
        [disabled removeObject:targetID];
        if (aliasMap[targetID]) [disabled removeObject:aliasMap[targetID]];
    } else {
        if (![disabled containsObject:targetID]) [disabled addObject:targetID];
        if (aliasMap[targetID] && ![disabled containsObject:aliasMap[targetID]]) [disabled addObject:aliasMap[targetID]];
    }

    [defaults setObject:disabled forKey:@"disabledPresetRules"];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
    [defaults synchronize];
    ads_post_notification();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (id)getCorelliumEnabled:(PSSpecifier *)spec {
    return @([ads_defaults() boolForKey:@"corelliumDecoyEnabled"]);
}

- (void)setCorelliumEnabled:(id)value specifier:(PSSpecifier *)spec {
    NSUserDefaults *defaults = ads_defaults();
    BOOL masterEnabled = [defaults boolForKey:@"enabled"];
    BOOL decoyEnabled = [value boolValue];

    [defaults setBool:decoyEnabled forKey:@"corelliumDecoyEnabled"];
    
    if (decoyEnabled) {
        NSMutableArray *disabled = [[defaults arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
        NSDictionary *aliasMap = ads_daemon_alias_map();
        BOOL changed = NO;
        for (NSString *shortName in @[@"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"]) {
            if ([disabled containsObject:shortName]) { [disabled removeObject:shortName]; changed = YES; }
            if (aliasMap[shortName] && [disabled containsObject:aliasMap[shortName]]) { [disabled removeObject:aliasMap[shortName]]; changed = YES; }
        }
        if (changed) {
            [defaults setObject:disabled forKey:@"disabledPresetRules"];
            [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
        }
    }

    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];

    pid_t pid;
    NSString *launchctl = ads_root_path(@"/usr/bin/launchctl");
    NSString *plistPath = ads_root_path(@"/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist");

    const char* unloadArgs[] = {"launchctl", "unload", plistPath.UTF8String, NULL};
    if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)unloadArgs, NULL) == 0) waitpid(pid, NULL, 0);

    if (masterEnabled && decoyEnabled) {
        const char* loadArgs[] = {"launchctl", "load", plistPath.UTF8String, NULL};
        if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)loadArgs, NULL) == 0) waitpid(pid, NULL, 0);
    }

    ads_post_notification();
    dispatch_async(dispatch_get_main_queue(), ^{ [self reloadSpecifiers]; });
}

- (id)getCountersEnabled:(PSSpecifier *)spec {
    return @([ads_defaults() boolForKey:@"countersEnabled"]);
}

- (void)setCountersEnabled:(id)value specifier:(PSSpecifier *)spec {
    NSUserDefaults *defaults = ads_defaults();
    [defaults setBool:[value boolValue] forKey:@"countersEnabled"];
    [defaults synchronize];
    ads_post_notification();
    dispatch_async(dispatch_get_main_queue(), ^{ [self reloadSpecifiers]; });
}

- (void)resetProbeCounter {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Counter" message:@"Clear the Corellium probe count?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSUserDefaults *defaults = ads_defaults();
        [defaults setInteger:0 forKey:@"corelliumProbeCount"];
        [defaults synchronize];
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadSpecifiers]; });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (id)getGlobalMitigation:(PSSpecifier *)specifier {
    return @([ads_defaults() boolForKey:[specifier propertyForKey:@"key"]]);
}

- (void)setGlobalMitigation:(id)value specifier:(PSSpecifier *)specifier {
    BOOL enabled = [value boolValue];
    NSString *key = [specifier propertyForKey:@"key"];
    NSUserDefaults *defaults = ads_defaults();
    
    if (enabled) {
        NSString *featureName = [specifier name];
        NSString *msg = [NSString stringWithFormat:@"Enabling '%@' globally applies this mitigation to ALL processes indiscriminately. This may break core functionality across the system and is intended for testing/emergency lockdown only.", featureName];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Warning" message:msg preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Enable Globally" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [defaults setBool:YES forKey:key];
            if ([key isEqualToString:@"globalDisableJS"]) {
                if (ads_is_ios16()) [defaults setBool:YES forKey:@"globalDisableJIT"];
                else [defaults setBool:YES forKey:@"globalDisableJIT15"];
            }
            [defaults setBool:YES forKey:@"ADSNeedsRespring"];
            [defaults synchronize];
            ads_post_notification();
            dispatch_async(dispatch_get_main_queue(), ^{ [self reloadSpecifiers]; });
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) { [self reloadSpecifiers]; }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [defaults setBool:NO forKey:key];
        if ([key isEqualToString:@"globalDisableJS"]) {
            [defaults setBool:NO forKey:@"globalDisableJIT"];
            [defaults setBool:NO forKey:@"globalDisableJIT15"];
        }
        [defaults setBool:YES forKey:@"ADSNeedsRespring"];
        [defaults synchronize];
        ads_post_notification();
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadSpecifiers]; });
    }
}
@end

@interface ATLApplicationListMultiSelectionController : PSListController
@end

@interface AntiDarkSwordAltListController : ATLApplicationListMultiSelectionController
@property (nonatomic, strong) NSArray *cachedPresetApps;
@property (nonatomic, strong) NSDictionary *cachedRestrictedApps;
@property (nonatomic, strong) NSDictionary *cachedRestrictedAppsLegacy;
@end

@implementation AntiDarkSwordAltListController
- (void)viewDidLoad {
    [super viewDidLoad];
    NSUserDefaults *defaults = ads_defaults();
    NSInteger level = [defaults integerForKey:@"autoProtectLevel"] ?: 1;
    AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];
    self.cachedPresetApps = [rootCtrl autoProtectedItemsForLevel:level];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSUserDefaults *defaults = ads_defaults();
    self.cachedRestrictedAppsLegacy = [defaults dictionaryForKey:@"restrictedApps"] ?: @{};
    self.cachedRestrictedApps = [defaults dictionaryRepresentation];
    [self reloadSpecifiers];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    
    NSString *bundleID = [spec propertyForKey:@"applicationIdentifier"];
    if (!bundleID) {
        NSString *alKey = [spec propertyForKey:@"ALSettingsKey"];
        if ([alKey hasPrefix:@"restrictedApps-"]) bundleID = [alKey substringFromIndex:@"restrictedApps-".length];
    }
    
    if (bundleID) {
        NSArray *presetApps = self.cachedPresetApps ?: @[];
        if ([cell respondsToSelector:@selector(control)]) {
            id control = [cell control];
            if ([control isKindOfClass:[UIView class]]) ((UIView *)control).hidden = YES;
        }
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        
        BOOL isManualRuleActive = NO;
        NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", bundleID];
        if (self.cachedRestrictedApps[prefKey] != nil) isManualRuleActive = [self.cachedRestrictedApps[prefKey] boolValue];
        else isManualRuleActive = [self.cachedRestrictedAppsLegacy[bundleID] boolValue];

        if ([presetApps containsObject:bundleID]) {
            cell.userInteractionEnabled = NO;
            cell.textLabel.alpha = 0.5;
            if (cell.detailTextLabel) cell.detailTextLabel.alpha = 0.5;
            cell.backgroundColor = [UIColor clearColor];
        } else {
            cell.userInteractionEnabled = YES;
            cell.textLabel.alpha = 1.0;
            if (cell.detailTextLabel) cell.detailTextLabel.alpha = 1.0;
            cell.backgroundColor = isManualRuleActive ? ads_color_green() : ads_color_red();
        }
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    NSString *bundleID = [spec propertyForKey:@"applicationIdentifier"];
    if (!bundleID) {
        NSString *alKey = [spec propertyForKey:@"ALSettingsKey"];
        if ([alKey hasPrefix:@"restrictedApps-"]) bundleID = [alKey substringFromIndex:@"restrictedApps-".length];
    }
    if (bundleID) {
        if ([self.cachedPresetApps ?: @[] containsObject:bundleID]) return;
        AntiDarkSwordAppController *detailController = [[AntiDarkSwordAppController alloc] init];
        detailController.targetID = bundleID;
        detailController.ruleType = 1; 
        detailController.rootController = self.rootController ?: self;
        detailController.parentController = self;
        
        PSSpecifier *dummySpec = [PSSpecifier preferenceSpecifierNamed:[spec name] ?: bundleID target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
        [dummySpec setProperty:bundleID forKey:@"targetID"];
        [dummySpec setProperty:@(1) forKey:@"ruleType"];
        [detailController setSpecifier:dummySpec];
        [self pushController:detailController];
    }
}
@end

@implementation AntiDarkSwordAppController
+ (BOOL)isDaemonTarget:(NSString *)targetID {
    if (!targetID) return NO;
    NSArray *daemons = @[@"com.apple.imagent", @"imagent", @"com.apple.apsd", @"apsd", @"com.apple.identityservicesd", @"identityservicesd", @"com.apple.IMDPersistenceAgent", @"IMDPersistenceAgent"];
    if ([daemons containsObject:targetID]) return YES;
    if (![targetID containsString:@"."] && ![targetID isEqualToString:@"pinterest"]) return YES;
    if ([targetID containsString:@"daemon"]) return YES;
    return NO;
}
+ (BOOL)isApplicableFeature:(NSString *)featureKey forTarget:(NSString *)targetID {
    BOOL isDaemon = [self isDaemonTarget:targetID];
    BOOL isMessageApp = [targetID isEqualToString:@"com.apple.MobileSMS"] || [targetID isEqualToString:@"com.apple.ActivityMessagesApp"] || [targetID isEqualToString:@"com.apple.iMessageAppsViewService"];
    if ([featureKey isEqualToString:@"disableIMessageDL"]) return isMessageApp;
    BOOL isIOS16 = ads_is_ios16();
    if ([featureKey isEqualToString:@"disableJIT"]) return isIOS16 && !isDaemon;
    if ([featureKey isEqualToString:@"disableJIT15"]) return !isIOS16 && !isDaemon;
    if ([featureKey isEqualToString:@"disableJS"] || [featureKey isEqualToString:@"disableRTC"] || [featureKey isEqualToString:@"disableMedia"] || [featureKey isEqualToString:@"disableFileAccess"]) return !isDaemon; 
    return YES;
}
- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    self.targetID = [specifier propertyForKey:@"targetID"];
    self.ruleType = [[specifier propertyForKey:@"ruleType"] integerValue];
    self.title = [specifier name] ?: self.targetID;
}
- (BOOL)isGlobalOverrideActiveForFeature:(NSString *)featureKey {
    NSUserDefaults *defaults = ads_defaults();
    NSInteger level = [defaults integerForKey:@"autoProtectLevel"] ?: 1;
    if (level < 3) return NO;
    if ([featureKey isEqualToString:@"spoofUA"]) return [defaults boolForKey:@"globalUASpoofingEnabled"];
    if ([featureKey isEqualToString:@"disableJIT"]) return [defaults boolForKey:@"globalDisableJIT"];
    if ([featureKey isEqualToString:@"disableJIT15"]) return [defaults boolForKey:@"globalDisableJIT15"];
    if ([featureKey isEqualToString:@"disableJS"]) return [defaults boolForKey:@"globalDisableJS"];
    if ([featureKey isEqualToString:@"disableRTC"]) return [defaults boolForKey:@"globalDisableRTC"];
    if ([featureKey isEqualToString:@"disableMedia"]) return [defaults boolForKey:@"globalDisableMedia"];
    if ([featureKey isEqualToString:@"disableIMessageDL"]) return [defaults boolForKey:@"globalDisableIMessageDL"];
    if ([featureKey isEqualToString:@"disableFileAccess"]) return [defaults boolForKey:@"globalDisableFileAccess"];
    return NO;
}
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        NSUserDefaults *defaults = ads_defaults();
        
        PSSpecifier *enableGroup = [PSSpecifier preferenceSpecifierNamed:@"Rule Status" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [specs addObject:enableGroup];
        PSSpecifier *enableSpec = [PSSpecifier preferenceSpecifierNamed:@"Enable Rule" target:self set:@selector(setMasterEnable:specifier:) get:@selector(getMasterEnable:) detail:nil cell:PSSwitchCell edit:nil];
        [specs addObject:enableSpec];
        
        BOOL isRuleEnabled = [[self getMasterEnable:enableSpec] boolValue];
        PSSpecifier *featGroup = [PSSpecifier preferenceSpecifierNamed:@"Mitigation Features" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [featGroup setProperty:@"Features not applicable to this target type, or currently enforced by a Global Rule, are locked." forKey:@"footerText"];
        [specs addObject:featGroup];
        
        NSArray *features = @[
            @{@"key": @"spoofUA", @"label": @"Spoof User Agent"},
            @{@"key": @"disableJIT", @"label": @"Disable JIT (iOS 16+)"},
            @{@"key": @"disableJIT15", @"label": @"Disable JIT (Legacy)"},
            @{@"key": @"disableJS", @"label": @"Disable JavaScript ⚠︎"},
            @{@"key": @"disableRTC", @"label": @"Disable WebGL & WebRTC"},
            @{@"key": @"disableMedia", @"label": @"Disable Media Auto-Play"},
            @{@"key": @"disableIMessageDL", @"label": @"Disable Msg Auto-Download"},
            @{@"key": @"disableFileAccess", @"label": @"Disable Local File Access"}
        ];
        
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID];
        NSDictionary *rules = [defaults dictionaryForKey:dictKey];
        BOOL isIOS16 = ads_is_ios16();
        BOOL isJSTurnedOn = (rules && rules[@"disableJS"] != nil) ? [rules[@"disableJS"] boolValue] : (!isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJS" forTarget:self.targetID]);
        
        for (NSDictionary *feat in features) {
            NSString *featKey = feat[@"key"];
            BOOL isApplicable = [AntiDarkSwordAppController isApplicableFeature:featKey forTarget:self.targetID];
            BOOL isGlobalOverride = [self isGlobalOverrideActiveForFeature:featKey];
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:feat[@"label"] target:self set:@selector(setFeatureValue:specifier:) get:@selector(getFeatureValue:) detail:nil cell:PSSwitchCell edit:nil];
            [spec setProperty:featKey forKey:@"featureKey"];
            
            if (isApplicable) {
                if (isGlobalOverride) [spec setProperty:@NO forKey:@"enabled"];
                else if (isIOS16 && isJSTurnedOn && [featKey isEqualToString:@"disableJIT"]) [spec setProperty:@NO forKey:@"enabled"];
                else if (!isIOS16 && isJSTurnedOn && [featKey isEqualToString:@"disableJIT15"]) [spec setProperty:@NO forKey:@"enabled"];
                else [spec setProperty:@(isRuleEnabled) forKey:@"enabled"];
            } else {
                [spec setProperty:@NO forKey:@"enabled"];
            }
            [specs addObject:spec];
        }
        _specifiers = [specs copy];
    }
    return _specifiers;
}
- (id)getMasterEnable:(PSSpecifier *)specifier {
    NSUserDefaults *defaults = ads_defaults();
    if (self.ruleType == 0) return @(![[defaults arrayForKey:@"disabledPresetRules"] ?: @[] containsObject:self.targetID]);
    else if (self.ruleType == 1) { 
        NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", self.targetID];
        if ([defaults objectForKey:prefKey]) return @([defaults boolForKey:prefKey]);
        return [defaults dictionaryForKey:@"restrictedApps"][self.targetID] ?: @NO;
    } else return @([[defaults arrayForKey:@"activeCustomDaemonIDs"] ?: [defaults arrayForKey:@"customDaemonIDs"] ?: @[] containsObject:self.targetID]);
}
- (void)setMasterEnable:(id)value specifier:(PSSpecifier *)specifier {
    NSUserDefaults *defaults = ads_defaults();
    BOOL enabled = [value boolValue];
    if (self.ruleType == 0) { 
        NSMutableArray *disabled = [[defaults arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
        if (enabled) [disabled removeObject:self.targetID];
        else if (![disabled containsObject:self.targetID]) [disabled addObject:self.targetID];
        [defaults setObject:disabled forKey:@"disabledPresetRules"];
    } else if (self.ruleType == 1) { 
        [defaults setBool:enabled forKey:[NSString stringWithFormat:@"restrictedApps-%@", self.targetID]];
        NSMutableDictionary *apps = [[defaults dictionaryForKey:@"restrictedApps"] mutableCopy];
        if (apps && apps[self.targetID]) { [apps removeObjectForKey:self.targetID]; [defaults setObject:apps forKey:@"restrictedApps"]; }
    } else { 
        NSMutableArray *active = [[defaults arrayForKey:@"activeCustomDaemonIDs"] mutableCopy] ?: [[defaults arrayForKey:@"customDaemonIDs"] mutableCopy] ?: [NSMutableArray array];
        if (enabled && ![active containsObject:self.targetID]) [active addObject:self.targetID];
        else if (!enabled) [active removeObject:self.targetID];
        [defaults setObject:active forKey:@"activeCustomDaemonIDs"];
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
    }
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    ads_post_notification();
    dispatch_async(dispatch_get_main_queue(), ^{ self->_specifiers = nil; [self reloadSpecifiers]; });
}
- (id)getFeatureValue:(PSSpecifier *)specifier {
    NSString *featureKey = [specifier propertyForKey:@"featureKey"];
    if (![AntiDarkSwordAppController isApplicableFeature:featureKey forTarget:self.targetID]) return @NO;
    if ([self isGlobalOverrideActiveForFeature:featureKey]) return @YES;

    NSUserDefaults *defaults = ads_defaults();
    NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID];
    NSDictionary *rules = [defaults dictionaryForKey:dictKey];
    
    if (!rules || rules[featureKey] == nil) { 
        AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];
        if (![[rootCtrl autoProtectedItemsForLevel:3] containsObject:self.targetID]) return @NO;

        NSInteger level = [defaults integerForKey:@"autoProtectLevel"] ?: 1;
        BOOL isIOS16 = ads_is_ios16();

        if ([featureKey isEqualToString:@"disableJIT"]) return @(isIOS16); 
        if ([featureKey isEqualToString:@"disableJIT15"]) return @(!isIOS16); 
        if ([featureKey isEqualToString:@"disableJS"]) return @(!isIOS16); 
        if ([featureKey isEqualToString:@"spoofUA"]) {
            if ([AntiDarkSwordAppController isDaemonTarget:self.targetID]) return @NO;
            if ([self.targetID isEqualToString:@"com.apple.mobilesafari"] || [self.targetID isEqualToString:@"com.apple.SafariViewService"]) return @YES;
            if ([self.targetID hasPrefix:@"com.apple."]) return @NO; 
            return @(level >= 2); 
        }
        if ([ads_msg_and_mail_apps() containsObject:self.targetID]) return @YES;
        if (level >= 3 && ([featureKey isEqualToString:@"disableRTC"] || [featureKey isEqualToString:@"disableMedia"])) {
            NSArray *browsers = @[@"com.apple.mobilesafari", @"com.apple.SafariViewService", @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios"];
            if ([browsers containsObject:self.targetID]) return @YES;
        }
        return @NO; 
    }
    return rules[featureKey];
}
- (void)setFeatureValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *featureKey = [specifier propertyForKey:@"featureKey"];
    if (![AntiDarkSwordAppController isApplicableFeature:featureKey forTarget:self.targetID]) return; 

    NSUserDefaults *defaults = ads_defaults();
    NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID];
    NSMutableDictionary *rules = [[defaults dictionaryForKey:dictKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    rules[featureKey] = value;
    
    if ([featureKey isEqualToString:@"disableJS"]) {
        BOOL isIOS16 = ads_is_ios16();
        if ([value boolValue]) {
            if (isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT" forTarget:self.targetID]) rules[@"disableJIT"] = @YES;
            else if (!isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT15" forTarget:self.targetID]) rules[@"disableJIT15"] = @YES;
        } else {
            rules[@"disableJIT"] = @NO;
            rules[@"disableJIT15"] = @NO;
        }
        [defaults setObject:rules forKey:dictKey];
        [defaults setBool:YES forKey:@"ADSNeedsRespring"];
        [defaults synchronize];
        dispatch_async(dispatch_get_main_queue(), ^{ self->_specifiers = nil; [self reloadSpecifiers]; });
        ads_post_notification();
        return;
    }
    [defaults setObject:rules forKey:dictKey];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    ads_post_notification();
}
@end

@implementation AntiDarkSwordPrefsRootListController
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSUserDefaults *defaults = ads_defaults();
    self.cachedDisabledPresetRules = [defaults arrayForKey:@"disabledPresetRules"] ?: @[];
    self.cachedActiveCustomDaemons = [defaults arrayForKey:@"activeCustomDaemonIDs"] ?: [defaults arrayForKey:@"customDaemonIDs"] ?: @[];
    [self reloadSpecifiers];
}
- (BOOL)isTargetInstalled:(NSString *)targetID {
    NSArray *coreServices = @[@"com.apple.imagent", @"com.apple.apsd", @"com.apple.identityservicesd", @"com.apple.IMDPersistenceAgent", @"com.apple.SafariViewService", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon", @"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"];
    if ([coreServices containsObject:targetID]) return YES;
    if (![targetID containsString:@"."] && ![targetID isEqualToString:@"pinterest"]) return YES; 
    @try {
        Class LSAppWorkspace = NSClassFromString(@"LSApplicationWorkspace");
        if (LSAppWorkspace) {
            LSApplicationWorkspace *workspace = [LSAppWorkspace defaultWorkspace];
            if (workspace && [workspace respondsToSelector:@selector(applicationIsInstalled:)]) if ([workspace applicationIsInstalled:targetID]) return YES;
        }
    } @catch (NSException *e) {}
    @try {
        Class LSAppProxy = NSClassFromString(@"LSApplicationProxy");
        if (LSAppProxy) {
            LSApplicationProxy *proxy = [LSAppProxy applicationProxyForIdentifier:targetID];
            if (proxy && [proxy respondsToSelector:@selector(bundleURL)]) {
                NSURL *bundleURL = [proxy bundleURL];
                if (bundleURL && [[NSFileManager defaultManager] fileExistsAtPath:bundleURL.path]) return YES;
            }
        }
    } @catch (NSException *e) {}
    return NO;
}
- (NSString *)displayNameForTargetID:(NSString *)targetID {
    NSDictionary *knownNames = @{
        @"imagent": @"iMessage Agent", @"apsd": @"Apple Push Service", @"identityservicesd": @"Identity Services", @"IMDPersistenceAgent": @"iMessage Persistence Agent",
        @"com.google.Gmail": @"Gmail", @"com.microsoft.Office.Outlook": @"Outlook", @"com.tinyspeck.chatlyio": @"Slack", @"com.microsoft.skype.teams": @"Microsoft Teams",
        @"com.google.chrome.ios": @"Chrome", @"com.brave.ios.browser": @"Brave", @"com.tumblr.tumblr": @"Tumblr", @"com.yahoo.Aerogram": @"Yahoo Mail",
        @"ch.protonmail.protonmail": @"Proton Mail", @"org.whispersystems.signal": @"Signal", @"ph.telegra.Telegraph": @"Telegram", @"com.facebook.Messenger": @"Messenger",
        @"com.toyopagroup.picaboo": @"Snapchat", @"com.tencent.xin": @"WeChat", @"com.viber": @"Viber", @"jp.naver.line": @"LINE", @"net.whatsapp.WhatsApp": @"WhatsApp",
        @"com.hammerandchisel.discord": @"Discord", @"com.google.GoogleMobile": @"Google", @"org.mozilla.ios.Firefox": @"Firefox", @"com.duckduckgo.mobile.ios": @"DuckDuckGo",
        @"pinterest": @"Pinterest", @"com.facebook.Facebook": @"Facebook", @"com.atebits.Tweetie2": @"X (Twitter)", @"com.burbn.instagram": @"Instagram",
        @"com.zhiliaoapp.musically": @"TikTok", @"com.linkedin.LinkedIn": @"LinkedIn", @"com.reddit.Reddit": @"Reddit", @"com.google.ios.youtube": @"YouTube",
        @"tv.twitch": @"Twitch", @"com.google.gemini": @"Google Gemini", @"com.openai.chat": @"ChatGPT", @"com.deepseek.chat": @"DeepSeek",
        @"com.github.stormbreaker.prod": @"GitHub", @"org.coolstar.SileoStore": @"Sileo", @"xyz.willy.Zebra": @"Zebra", @"com.tigisoftware.Filza": @"Filza",
        @"com.apple.Passbook": @"Apple Wallet", @"com.squareup.cash": @"Cash App", @"net.kortina.labs.Venmo": @"Venmo", @"com.yourcompany.PPClient": @"PayPal",
        @"com.robinhood.release.Robinhood": @"Robinhood", @"com.vilcsak.bitcoin2": @"Coinbase", @"com.sixdays.trust": @"Trust Wallet", @"io.metamask.MetaMask": @"MetaMask",
        @"app.phantom.phantom": @"Phantom", @"com.chase": @"Chase", @"com.bankofamerica.BofAMobileBanking": @"Bank of America", @"com.wellsfargo.net.mobilebanking": @"Wells Fargo",
        @"com.citi.citimobile": @"Citi", @"com.capitalone.enterprisemobilebanking": @"Capital One", @"com.americanexpress.amelia": @"Amex", @"com.fidelity.iphone": @"Fidelity",
        @"com.schwab.mobile": @"Charles Schwab", @"com.etrade.mobilepro.iphone": @"E*TRADE", @"com.discoverfinancial.mobile": @"Discover", @"com.usbank.mobilebanking": @"U.S. Bank",
        @"com.monzo.ios": @"Monzo", @"com.revolut.iphone": @"Revolut", @"com.binance.dev": @"Binance", @"com.kraken.invest": @"Kraken",
        @"com.barclays.ios.bmb": @"Barclays", @"com.ally.auto": @"Ally", @"com.navyfederal.navyfederal.mydata": @"Navy Federal", @"com.1debit.ChimeProdApp": @"Chime"
    };
    if (knownNames[targetID]) return knownNames[targetID];
    if (![targetID containsString:@"."] && ![targetID isEqualToString:@"pinterest"]) return targetID; 
    NSArray *daemons = @[@"com.apple.imagent", @"com.apple.apsd", @"com.apple.identityservicesd", @"com.apple.IMDPersistenceAgent", @"com.apple.SafariViewService", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"];
    if ([daemons containsObject:targetID]) return targetID;
    @try {
        Class LSAppProxy = NSClassFromString(@"LSApplicationProxy");
        if (LSAppProxy) {
            id proxy = [LSAppProxy applicationProxyForIdentifier:targetID];
            if (proxy && [proxy respondsToSelector:@selector(localizedName)]) {
                NSString *name = [proxy localizedName];
                if (name && name.length > 0) return name;
            }
        }
    } @catch (NSException *e) {}
    return targetID;
}
- (UIImage *)iconForTargetID:(NSString *)targetID {
    UIImage *icon = nil;
    if ([targetID containsString:@"."] || [targetID isEqualToString:@"pinterest"]) {
        NSArray *daemons = @[@"com.apple.imagent", @"com.apple.apsd", @"com.apple.identityservicesd", @"com.apple.IMDPersistenceAgent", @"com.apple.SafariViewService", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon", @"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"];
        if (![daemons containsObject:targetID]) {
            @try {
                if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) icon = [UIImage _applicationIconImageForBundleIdentifier:targetID format:29 scale:[UIScreen mainScreen].scale];
            } @catch (NSException *e) {}
        }
    }
    if (!icon) {
        if (@available(iOS 13.0, *)) {
            icon = [UIImage systemImageNamed:@"gearshape.fill"];
            icon = [icon imageWithTintColor:[UIColor systemGrayColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    }
    if (icon) {
        CGSize newSize = CGSizeMake(23, 23);
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:newSize];
        return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [icon drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)]; }];
    }
    return nil;
}
- (void)populateDefaultRulesForLevel:(NSInteger)level force:(BOOL)force {
    NSUserDefaults *defaults = ads_defaults();
    if (!force && [defaults boolForKey:@"hasInitializedDefaultRules"]) return;
    BOOL isIOS16 = ads_is_ios16();
    NSArray *browsers = @[@"com.apple.mobilesafari", @"com.apple.SafariViewService", @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios"];
    NSArray *msgAndMail = ads_msg_and_mail_apps();
    NSArray *allProtected = [self autoProtectedItemsForLevel:3];
    NSMutableArray *expandedTargets = [NSMutableArray arrayWithArray:allProtected];
    [expandedTargets addObjectsFromArray:@[@"com.apple.imagent", @"imagent", @"com.apple.apsd", @"apsd", @"com.apple.identityservicesd", @"identityservicesd", @"com.apple.IMDPersistenceAgent", @"IMDPersistenceAgent"]];

    for (NSString *targetID in expandedTargets) {
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", targetID];
        if (!force && [defaults objectForKey:dictKey]) continue;
        NSMutableDictionary *rules = [NSMutableDictionary dictionary];
        rules[@"disableJIT"] = (isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT" forTarget:targetID]) ? @YES : @NO; 
        rules[@"disableJIT15"] = (!isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT15" forTarget:targetID]) ? @YES : @NO; 
        rules[@"disableJS"] = (!isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJS" forTarget:targetID]) ? @YES : @NO; 
        rules[@"disableMedia"] = @NO; rules[@"disableRTC"] = @NO; rules[@"disableFileAccess"] = @NO; rules[@"disableIMessageDL"] = @NO; rules[@"spoofUA"] = @NO;
        
        if ([msgAndMail containsObject:targetID]) {
            rules[@"disableMedia"] = [AntiDarkSwordAppController isApplicableFeature:@"disableMedia" forTarget:targetID] ? @YES : @NO;
            rules[@"disableRTC"] = [AntiDarkSwordAppController isApplicableFeature:@"disableRTC" forTarget:targetID] ? @YES : @NO;
            rules[@"disableFileAccess"] = [AntiDarkSwordAppController isApplicableFeature:@"disableFileAccess" forTarget:targetID] ? @YES : @NO;
            rules[@"disableIMessageDL"] = [AntiDarkSwordAppController isApplicableFeature:@"disableIMessageDL" forTarget:targetID] ? @YES : @NO;
            if (![targetID hasPrefix:@"com.apple."]) rules[@"spoofUA"] = (level >= 2) ? @YES : @NO;
        } else if ([browsers containsObject:targetID]) {
            if ([targetID isEqualToString:@"com.apple.mobilesafari"] || [targetID isEqualToString:@"com.apple.SafariViewService"]) rules[@"spoofUA"] = @YES;
            else rules[@"spoofUA"] = (level >= 2) ? @YES : @NO;
            if (level >= 3) { rules[@"disableRTC"] = @YES; rules[@"disableMedia"] = @YES; }
        } else if (![AntiDarkSwordAppController isDaemonTarget:targetID]) {
            if (![targetID hasPrefix:@"com.apple."]) rules[@"spoofUA"] = (level >= 2) ? @YES : @NO;
        }
        [defaults setObject:rules forKey:dictKey];
    }
    [defaults setBool:YES forKey:@"hasInitializedDefaultRules"];
    [defaults synchronize];
}
- (NSArray *)autoProtectedItemsForLevel:(NSInteger)level {
    NSMutableArray *items = [NSMutableArray array];
    NSArray *tier1 = @[@"com.apple.mobilesafari", @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.mobilenotes", @"com.apple.iBooks", @"com.apple.news", @"com.apple.podcasts", @"com.apple.stocks", @"com.apple.SafariViewService", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"];
    NSArray *tier2ThirdParty = @[@"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", @"ch.protonmail.protonmail", @"org.whispersystems.signal", @"ph.telegra.Telegraph", @"com.facebook.Messenger", @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio", @"com.microsoft.skype.teams", @"com.tencent.xin", @"com.viber", @"jp.naver.line", @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.google.GoogleMobile", @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios", @"pinterest", @"com.tumblr.tumblr", @"com.facebook.Facebook", @"com.atebits.Tweetie2", @"com.burbn.instagram", @"com.zhiliaoapp.musically", @"com.linkedin.LinkedIn", @"com.reddit.Reddit", @"com.google.ios.youtube", @"tv.twitch", @"com.google.gemini", @"com.openai.chat", @"com.deepseek.chat", @"com.github.stormbreaker.prod", @"com.squareup.cash", @"net.kortina.labs.Venmo", @"com.yourcompany.PPClient", @"com.robinhood.release.Robinhood", @"com.vilcsak.bitcoin2", @"com.sixdays.trust", @"io.metamask.MetaMask", @"app.phantom.phantom", @"com.chase", @"com.bankofamerica.BofAMobileBanking", @"com.wellsfargo.net.mobilebanking", @"com.citi.citimobile", @"com.capitalone.enterprisemobilebanking", @"com.americanexpress.amelia", @"com.fidelity.iphone", @"com.schwab.mobile", @"com.etrade.mobilepro.iphone", @"com.discoverfinancial.mobile", @"com.usbank.mobilebanking", @"com.monzo.ios", @"com.revolut.iphone", @"com.binance.dev", @"com.kraken.invest", @"com.barclays.ios.bmb", @"com.ally.auto", @"com.navyfederal.navyfederal.mydata", @"com.1debit.ChimeProdApp"];
    NSArray *sortedTier2 = [tier2ThirdParty sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        NSString *nameA = [self displayNameForTargetID:a];
        NSString *nameB = [self displayNameForTargetID:b];
        return [nameA caseInsensitiveCompare:nameB];
    }];
    NSArray *tier2JB = @[ @"org.coolstar.SileoStore", @"xyz.willy.Zebra", @"com.tigisoftware.Filza" ];
    
    [items addObjectsFromArray:tier1];
    if (level >= 2) { [items addObjectsFromArray:sortedTier2]; [items addObjectsFromArray:tier2JB]; }
    return items;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];

    if (spec->action == @selector(resetToDefaults)) {
        if (@available(iOS 13.0, *)) cell.textLabel.textColor = [UIColor systemRedColor];
        else cell.textLabel.textColor = [UIColor redColor];
    }
    if ([[spec propertyForKey:@"key"] isEqualToString:@"enabled"]) {
        if ([cell respondsToSelector:@selector(control)]) {
            UISwitch *toggle = (UISwitch *)[cell control];
            if ([toggle isKindOfClass:[UISwitch class]]) {
                if (@available(iOS 13.0, *)) toggle.backgroundColor = [UIColor systemRedColor];
                else toggle.backgroundColor = [UIColor redColor];
                toggle.layer.cornerRadius = 15.5; 
            }
        }
    }
    id ruleTypeObj = [spec propertyForKey:@"ruleType"];
    if (ruleTypeObj != nil) {
        NSString *targetID = [spec propertyForKey:@"targetID"];
        NSInteger ruleType = [ruleTypeObj integerValue];
        BOOL isEnabled = YES;
        if (ruleType == 0) {
            NSArray *disabled = self.cachedDisabledPresetRules ?: @[];
            isEnabled = ![disabled containsObject:targetID];
        } else if (ruleType == 2) {
            NSArray *active = self.cachedActiveCustomDaemons ?: @[];
            isEnabled = [active containsObject:targetID];
        }
        cell.backgroundColor = isEnabled ? ads_color_green() : ads_color_red();
    } else {
        if (@available(iOS 13.0, *)) cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        else cell.backgroundColor = [UIColor whiteColor];
    }
    return cell;
}
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        NSUserDefaults *defaults = ads_defaults();
        NSString *selectedUA = [defaults stringForKey:@"selectedUAPreset"];
        if (!selectedUA || [selectedUA isEqualToString:@"NONE"]) {
            selectedUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
            [defaults setObject:selectedUA forKey:@"selectedUAPreset"];
            [defaults synchronize];
        }

        if (![selectedUA isEqualToString:@"CUSTOM"]) {
            for (int i = 0; i < specs.count; i++) {
                PSSpecifier *s = specs[i];
                if ([[s propertyForKey:@"id"] isEqualToString:@"CustomUATextField"]) { [specs removeObjectAtIndex:i]; break; }
            }
        }
        
        NSInteger autoProtectLevel = [defaults objectForKey:@"autoProtectLevel"] ? [defaults integerForKey:@"autoProtectLevel"] : 1;
        NSArray *customIDs = [defaults objectForKey:@"customDaemonIDs"] ?: @[];
        
        for (PSSpecifier *s in specs) {
            if ([[s propertyForKey:@"id"] isEqualToString:@"SelectApps"]) s.detailControllerClass = [AntiDarkSwordAltListController class];
            if ([s.identifier isEqualToString:@"PresetRulesGroup"]) {
                NSString *footerText = @"";
                if (autoProtectLevel == 1) footerText = @"Level 1: Protects native Apple applications, including Safari, Messages, Mail, Notes, Calendar, Wallet, and other built-in iOS apps.";
                else if (autoProtectLevel == 2) footerText = @"Level 2: Expands protection to major 3rd-party web browsers, email clients, messaging platforms, social media apps, package managers, and finance/crypto apps.";
                else if (autoProtectLevel == 3) footerText = @"Level 3: Maximum protection. Restricts system background daemons, configure in Level 3 Settings.";
                [s setProperty:footerText forKey:@"footerText"];
            }
            if ([[s propertyForKey:@"id"] isEqualToString:@"SystemOptionsCell"]) {
                if (autoProtectLevel < 3) {
                    [s setProperty:@NO forKey:@"enabled"];
                    s.name = @"🔒  Level 3 Settings";
                } else {
                    [s setProperty:@YES forKey:@"enabled"];
                    s.name = @"⚙️  Level 3 Settings";
                }
            }
            if ([[s propertyForKey:@"id"] isEqualToString:@"FooterGroup"]) {
                NSString *osVersion = [[UIDevice currentDevice] systemVersion];
                NSBundle *bundle = [NSBundle bundleForClass:[self class]];
                NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"4.2.9";
                NSString *jbType = @"Rootless";
                if (access("/Library/MobileSubstrate/DynamicLibraries", F_OK) == 0) jbType = @"Rootful";
                if (dlsym(RTLD_DEFAULT, "jbroot")) jbType = @"Roothide";
                NSString *footerString = [NSString stringWithFormat:@"AntiDarkSword v%@ (iOS %@ %@)", version, osVersion, jbType];
                [s setProperty:footerString forKey:@"footerText"];
                [s setProperty:@(1) forKey:@"footerAlignment"]; 
            }
        }

        NSUInteger insertIndexAuto = [specs indexOfObjectPassingTest:^BOOL(PSSpecifier *obj, NSUInteger idx, BOOL *stop) { return [[obj propertyForKey:@"id"] isEqualToString:@"AutoProtectLevelSegment"]; }];
        
        if (insertIndexAuto != NSNotFound) {
            insertIndexAuto++;
            PSSpecifier *groupSpec = [PSSpecifier preferenceSpecifierNamed:@"Current Preset Rules" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            [specs insertObject:groupSpec atIndex:insertIndexAuto++];
            NSArray *autoItems = [self autoProtectedItemsForLevel:autoProtectLevel];
            for (NSString *item in autoItems) {
                if (![self isTargetInstalled:item]) continue; 
                NSString *displayName = [self displayNameForTargetID:item];
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:displayName target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
                [spec setProperty:item forKey:@"targetID"];
                [spec setProperty:@(0) forKey:@"ruleType"];
                UIImage *icon = [self iconForTargetID:item];
                if (icon) [spec setProperty:icon forKey:@"iconImage"];
                [specs insertObject:spec atIndex:insertIndexAuto++];
            }
        }
        
        NSUInteger insertIndexCustom = [specs indexOfObjectPassingTest:^BOOL(PSSpecifier *obj, NSUInteger idx, BOOL *stop) { return [[obj propertyForKey:@"id"] isEqualToString:@"AddCustomIDButton"]; }];
        if (insertIndexCustom != NSNotFound) {
            insertIndexCustom++;
            for (NSString *daemonID in customIDs) {
                NSString *displayName = [self displayNameForTargetID:daemonID];
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:displayName target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
                [spec setProperty:daemonID forKey:@"targetID"];
                [spec setProperty:daemonID forKey:@"daemonID"];
                [spec setProperty:@(2) forKey:@"ruleType"]; 
                [spec setProperty:@YES forKey:@"isCustomDaemon"];
                UIImage *icon = [self iconForTargetID:daemonID];
                if (icon) [spec setProperty:icon forKey:@"iconImage"];
                [specs insertObject:spec atIndex:insertIndexCustom++];
            }
        }
        _specifiers = [specs copy];
    }
    return _specifiers;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    NSUserDefaults *defaults = ads_defaults();
    NSInteger currentLevel = [defaults objectForKey:@"autoProtectLevel"] ? [defaults integerForKey:@"autoProtectLevel"] : 1;
    [self populateDefaultRulesForLevel:currentLevel force:NO];
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(savePrompt)];
    self.navigationItem.rightBarButtonItem = saveButton;
    BOOL isEnabled = [defaults boolForKey:@"enabled"];
    BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
    saveButton.enabled = needsRespring || (isEnabled && needsReboot);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (CFNotificationCallback)PrefsChangedNotification, ADS_NOTIF_SAVED, NULL, CFNotificationSuspensionBehaviorCoalesce);
    [self setupHeaderView];
}
- (void)setupHeaderView {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *imagePath = [bundle pathForResource:@"banner" ofType:@"png"];
    UIImage *bannerImage = [UIImage imageWithContentsOfFile:imagePath];
    if (bannerImage) {
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        CGFloat aspect = bannerImage.size.height / bannerImage.size.width;
        CGFloat height = screenWidth * aspect;
        UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenWidth, height)];
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:headerView.bounds];
        imageView.image = bannerImage;
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        imageView.clipsToBounds = YES;
        [headerView addSubview:imageView];
        self.table.tableHeaderView = headerView;
    }
}
- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), ADS_NOTIF_SAVED, NULL);
}
static void PrefsChangedNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    AntiDarkSwordPrefsRootListController *controller = (__bridge AntiDarkSwordPrefsRootListController *)observer;
    if (controller) {
        NSUserDefaults *defaults = ads_defaults();
        BOOL isEnabled = [defaults boolForKey:@"enabled"];
        BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
        BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
        dispatch_async(dispatch_get_main_queue(), ^{
            controller.navigationItem.rightBarButtonItem.enabled = needsRespring || (isEnabled && needsReboot);
        });
    }
}
- (void)flagSaveRequirement {
    NSUserDefaults *defaults = ads_defaults();
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    BOOL isEnabled = [defaults boolForKey:@"enabled"];
    BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
    self.navigationItem.rightBarButtonItem.enabled = needsRespring || (isEnabled && needsReboot);
}
- (void)setEnableProtection:(id)value specifier:(PSSpecifier *)specifier {
    [self setPreferenceValue:value specifier:specifier];
    NSUserDefaults *defaults = ads_defaults();
    NSInteger level = [defaults integerForKey:@"autoProtectLevel"];
    NSArray *customDaemons = [defaults arrayForKey:@"activeCustomDaemonIDs"] ?: @[];
    BOOL masterEnabled = [value boolValue];
    BOOL decoyEnabled = [defaults boolForKey:@"corelliumDecoyEnabled"];
    pid_t pid;
    NSString *launchctl = ads_root_path(@"/usr/bin/launchctl");
    NSString *plistPath = ads_root_path(@"/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist");
    const char* unloadArgs[] = {"launchctl", "unload", plistPath.UTF8String, NULL};
    if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)unloadArgs, NULL) == 0) waitpid(pid, NULL, 0);
    if (masterEnabled && decoyEnabled) {
        const char* loadArgs[] = {"launchctl", "load", plistPath.UTF8String, NULL};
        if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)loadArgs, NULL) == 0) waitpid(pid, NULL, 0);
    }
    if (level >= 3 || customDaemons.count > 0) {
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
        [defaults synchronize];
    }
    [self savePrompt];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSUserDefaults *defaults = ads_defaults();
    if ([key isEqualToString:@"customUAString"]) {
        NSString *input = (NSString *)value;
        NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            NSString *ios18UA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
            value = ios18UA;
            [defaults setObject:ios18UA forKey:@"selectedUAPreset"];
            [defaults synchronize];
            dispatch_async(dispatch_get_main_queue(), ^{ self->_specifiers = nil; [self reloadSpecifiers]; });
        }
    }
    [super setPreferenceValue:value specifier:specifier];
    [self flagSaveRequirement];
    if ([key isEqualToString:@"selectedUAPreset"]) { _specifiers = nil; [self reloadSpecifiers]; }
}
- (void)setAutoProtectLevel:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = ads_defaults();
    NSInteger oldLevel = [defaults integerForKey:@"autoProtectLevel"];
    NSInteger newLevel = [value integerValue];
    [defaults setObject:value forKey:@"autoProtectLevel"];
    if (oldLevel != newLevel) [self populateDefaultRulesForLevel:newLevel force:YES];
    if (oldLevel >= 3 || newLevel >= 3) [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
    
    if (newLevel >= 3 && ![defaults boolForKey:@"corelliumDecoyEnabled"]) {
        [defaults setBool:YES forKey:@"corelliumDecoyEnabled"];
        NSDictionary *aliasMap = ads_daemon_alias_map();
        NSArray *daemonShortNames = @[@"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"];
        NSMutableArray *disabled = [[defaults arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
        BOOL daemonsChanged = NO;
        for (NSString *shortName in daemonShortNames) {
            if ([disabled containsObject:shortName]) { [disabled removeObject:shortName]; daemonsChanged = YES; }
            NSString *bundleAlias = aliasMap[shortName];
            if (bundleAlias && [disabled containsObject:bundleAlias]) { [disabled removeObject:bundleAlias]; daemonsChanged = YES; }
        }
        if (daemonsChanged) [defaults setObject:disabled forKey:@"disabledPresetRules"];
        if ([defaults boolForKey:@"enabled"]) {
            pid_t pid;
            NSString *launchctl = ads_root_path(@"/usr/bin/launchctl");
            NSString *plistPath = ads_root_path(@"/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist");
            const char* loadArgs[] = {"launchctl", "load", plistPath.UTF8String, NULL};
            if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)loadArgs, NULL) == 0) waitpid(pid, NULL, 0);
        }
    } else if (newLevel < 3 && [defaults boolForKey:@"corelliumDecoyEnabled"]) {
        [defaults setBool:NO forKey:@"corelliumDecoyEnabled"];
        pid_t pid;
        NSString *launchctl = ads_root_path(@"/usr/bin/launchctl");
        NSString *plistPath = ads_root_path(@"/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist");
        const char *unloadArgs[] = {"launchctl", "unload", plistPath.UTF8String, NULL};
        if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)unloadArgs, NULL) == 0) waitpid(pid, NULL, 0);
    }
    [defaults synchronize];
    [self flagSaveRequirement];
    ads_post_notification();
    dispatch_async(dispatch_get_main_queue(), ^{ self->_specifiers = nil; [self reloadSpecifiers]; });
}
- (void)addCustomID {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Custom ID" message:@"Enter bundle IDs or process names (comma-separated)" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) { textField.placeholder = @"com.apple.imagent, apsd"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *inputText = alert.textFields.firstObject.text;
        if (inputText.length > 0) {
            NSArray *inputIDs = [inputText componentsSeparatedByString:@","];
            NSUserDefaults *defaults = ads_defaults();
            NSMutableArray *customIDs = [[defaults objectForKey:@"customDaemonIDs"] ?: @[] mutableCopy];
            NSMutableArray *activeCustom = [[defaults objectForKey:@"activeCustomDaemonIDs"] ?: customIDs mutableCopy];
            BOOL changesMade = NO;
            for (NSString *rawID in inputIDs) {
                NSString *cleanID = [rawID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (cleanID.length > 0 && ![customIDs containsObject:cleanID]) {
                    [customIDs addObject:cleanID];
                    if (![activeCustom containsObject:cleanID]) [activeCustom addObject:cleanID];
                    changesMade = YES;
                }
            }
            if (changesMade) {
                [defaults setObject:customIDs forKey:@"customDaemonIDs"];
                [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"];
                [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
                [defaults synchronize];
                [self flagSaveRequirement];
                _specifiers = nil;
                [self reloadSpecifiers];
                ads_post_notification();
            }
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    return [[spec propertyForKey:@"isCustomDaemon"] boolValue];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
        NSString *daemonID = [spec propertyForKey:@"daemonID"];
        NSUserDefaults *defaults = ads_defaults();
        NSMutableArray *customIDs = [[defaults objectForKey:@"customDaemonIDs"] ?: @[] mutableCopy];
        NSMutableArray *activeCustom = [[defaults objectForKey:@"activeCustomDaemonIDs"] ?: customIDs mutableCopy];
        [customIDs removeObject:daemonID];
        [activeCustom removeObject:daemonID];
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", daemonID];
        [defaults removeObjectForKey:dictKey];
        [defaults setObject:customIDs forKey:@"customDaemonIDs"];
        [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"];
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
        [defaults synchronize];
        [self flagSaveRequirement];
        [self removeSpecifier:spec animated:YES];
        ads_post_notification();
    }
}
- (void)resetToDefaults {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset to Defaults" message:@"Userspace reboot required to completely flush daemon hooks." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reboot Userspace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        pid_t pid;
        NSString *launchctl = ads_root_path(@"/usr/bin/launchctl");
        NSString *plistPath = ads_root_path(@"/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist");
        const char* unloadArgs[] = {"launchctl", "unload", plistPath.UTF8String, NULL};
        if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)unloadArgs, NULL) == 0) waitpid(pid, NULL, 0);
        NSUserDefaults *defaults = ads_defaults();
        [defaults removePersistentDomainForName:ADS_PREFS_SUITE];
        [defaults synchronize];
        ads_post_notification();
        const char* rebootArgs[] = {"launchctl", "reboot", "userspace", NULL};
        posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)rebootArgs, NULL);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)savePrompt {
    NSUserDefaults *defaults = ads_defaults();
    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
    NSString *title = @"Save";
    NSString *msg = needsReboot ? @"Apply changes with a userspace reboot? (Required for daemon changes)" : @"Apply changes with respring?";
    NSString *btn = needsReboot ? @"Reboot Userspace" : @"Respring";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:btn style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [defaults setBool:NO forKey:@"ADSNeedsRespring"];
        [defaults setBool:NO forKey:@"ADSPendingDaemonChanges"];
        [defaults synchronize];
        
        pid_t pid;
        NSString *launchctl = ads_root_path(@"/usr/bin/launchctl");
        NSString *killall = ads_root_path(@"/usr/bin/killall");
        
        if (needsReboot) {
            const char* args[] = {"launchctl", "reboot", "userspace", NULL};
            posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)args, NULL);
        } else {
            ads_kill_all_apps();
            const char* args[] = {"killall", "backboardd", NULL};
            if (posix_spawn(&pid, killall.UTF8String, NULL, NULL, (char* const*)args, NULL) == 0) waitpid(pid, NULL, 0);
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)openGitHub {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/EolnMsuk/AntiDarkSword"] options:@{} completionHandler:nil];
}
- (void)openVenmo {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://venmo.com/user/eolnmsuk"] options:@{} completionHandler:nil];
}
@end