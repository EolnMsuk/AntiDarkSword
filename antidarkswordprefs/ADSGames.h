#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <SpriteKit/SpriteKit.h>
#import <CoreImage/CoreImage.h>

#define ADS_PREFS_SUITE @"com.eolnmsuk.antidarkswordprefs"

typedef struct {
    float bgmPhase;
    float bgmPhase2;
    float bgmPhase3;
    float sfxPhase;
    float sfxFreq;
    float sfxDur;
    float sfxEnvInit;
    float sfxFreq2;
    float sfxPhase2;
    float sfxDur2;
    float bgmTime;
    float bgmTime2;
    int bgmIdx;
    int bgmIdx2;
    int playBGM;
    float sfxSweepRate;
    float sfxSweep2Rate;
} ADSSynthState;

typedef NS_ENUM(NSInteger, ADSGameState) {
    ADSGameStateMenu,
    ADSGameStatePlaying,
    ADSGameStatePaused,
    ADSGameStateDead
};

@interface ADSGameMenuScene : SKScene
@property (nonatomic, copy) void (^onSelectGame)(NSInteger gameIndex);
@property (nonatomic, copy) void (^exitHandler)(void);
@end

@interface ADSJailTrisScene : SKScene
@property (nonatomic, copy) void (^exitHandler)(void);
@end

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

@interface AntiDarkSwordCreditsController : PSListController
@end