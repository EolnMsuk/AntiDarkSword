#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <SpriteKit/SpriteKit.h>
#import <CoreImage/CoreImage.h>

// Shared preference suite string
#define ADS_PREFS_SUITE @"com.eolnmsuk.antidarkswordprefs"

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

@interface ADSJailTrisScene : SKScene
@property (nonatomic, copy) void (^exitHandler)(void);
@end

// --- PYEATER SCENE ---
@interface ADSPyEaterScene : SKScene
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
@property (nonatomic, strong) SKLabelNode *menuBtn;
@property (nonatomic, strong) SKLabelNode *highScoreBtn;

@property (nonatomic, copy) void (^exitHandler)(void);
@end

// --- CREDITS CONTROLLER ---
@interface AntiDarkSwordCreditsController : PSListController
@end