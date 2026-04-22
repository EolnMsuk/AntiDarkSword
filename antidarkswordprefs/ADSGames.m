#import "ADSGames.h"
#import <AVFoundation/AVFoundation.h>

typedef struct {
    float bgmPhase;
    float sfxPhase;
    float sfxFreq;
    float sfxDur;
    float bgmTime;
    int bgmIdx;
    int playBGM;
} ADSSynthState;

@interface ADSPyEaterScene ()
@property (nonatomic, strong) SKLabelNode *musicBtn;
@property (nonatomic, strong) SKShapeNode *musicBtnBg;
@property (nonatomic, strong) SKNode *deathContainer;
@end

@interface ADSJailTrisScene ()
@property (nonatomic, strong) SKLabelNode *musicBtn;
@property (nonatomic, strong) SKShapeNode *musicBtnBg;
@end

// --- PYEATER SCENE ---
@implementation ADSPyEaterScene {
    CGPoint _touchStartLoc;
    AVAudioEngine *_audioEngine;
    AVAudioSourceNode *_sourceNode;
    ADSSynthState *_synthState;
    BOOL _musicEnabled;
}
static const CGFloat kGridSize = 20.0;

- (int)minX { return 2; }
- (int)maxX { return (self.size.width / kGridSize) - 2; }
- (int)minY { return 4; } 
- (int)maxY { return (self.size.height / kGridSize) - 3; } 

- (void)willMoveFromView:(SKView *)view {
    if (_audioEngine) {
        [_audioEngine stop];
        _audioEngine = nil;
    }
    if (_synthState) {
        free(_synthState);
        _synthState = NULL;
    }
    NSArray *gestures = [view.gestureRecognizers copy];
    for (UIGestureRecognizer *g in gestures) {
        [view removeGestureRecognizer:g];
    }
}

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
    
    [self setupAudio];
    [self setupGestures:view];
    [self setupUI];
    [self drawWalls];
    
    self.gameState = ADSGameStateMenu;
    self.snake = [NSMutableArray array];
}

- (void)setupAudio {
    _synthState = malloc(sizeof(ADSSynthState));
    memset(_synthState, 0, sizeof(ADSSynthState));
    _musicEnabled = NO;
    _synthState->playBGM = 0;
    
    _audioEngine = [[AVAudioEngine alloc] init];
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:1];
    ADSSynthState *state = _synthState;
    
    _sourceNode = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *ts, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
        float *outBuf = (float *)outputData->mBuffers[0].mData;
        float pyeaterTune[] = { 440.00, 523.25, 659.25, 880.00, 783.99, 659.25, 523.25, 587.33 }; 
        for (AVAudioFrameCount i = 0; i < frameCount; i++) {
            float bgmSamp = 0;
            if (state->playBGM) {
                state->bgmTime += 1.0/44100.0;
                if (state->bgmTime > 0.12) {
                    state->bgmTime = 0;
                    state->bgmIdx = (state->bgmIdx + 1) % 8;
                }
                float bFreq = pyeaterTune[state->bgmIdx];
                if (bFreq > 0) {
                    state->bgmPhase += (bFreq * 2.0 * M_PI) / 44100.0;
                    if (state->bgmPhase > 2.0 * M_PI) state->bgmPhase -= 2.0 * M_PI;
                    bgmSamp = (state->bgmPhase < M_PI ? 0.01 : -0.01); 
                }
            }
            float sfxSamp = 0;
            if (state->sfxDur > 0) {
                state->sfxPhase += (state->sfxFreq * 2.0 * M_PI) / 44100.0;
                if (state->sfxPhase > 2.0 * M_PI) state->sfxPhase -= 2.0 * M_PI;
                sfxSamp = (state->sfxPhase < M_PI ? 0.2 : -0.2); 
                state->sfxDur -= 1.0/44100.0;
            }
            outBuf[i] = bgmSamp + sfxSamp;
        }
        return noErr;
    }];
    
    [_audioEngine attachNode:_sourceNode];
    [_audioEngine connect:_sourceNode to:_audioEngine.mainMixerNode format:format];
    [_audioEngine startAndReturnError:nil];
}

- (void)playSFX:(float)freq dur:(float)dur {
    if (_synthState) { _synthState->sfxFreq = freq; _synthState->sfxDur = dur; }
}

- (void)setupUI {
    self.titleLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.titleLbl.text = @"PyEater";
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
    CGFloat overlayH = (self.size.height - 120) / 2.0;
    self.restartOverlay = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(overlayW, overlayH) cornerRadius:15];
    self.restartOverlay.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    self.restartOverlay.fillColor = [UIColor clearColor]; 
    self.restartOverlay.strokeColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    self.restartOverlay.lineWidth = 4.0;
    self.restartOverlay.zPosition = 50;
    self.restartOverlay.hidden = YES;
    [self.bloomNode addChild:self.restartOverlay];

    self.startBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.startBtn.text = @"▶ EXECUTE";
    self.startBtn.fontColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    self.startBtn.fontSize = 40;
    self.startBtn.position = CGPointMake(self.size.width / 2, self.size.height / 2 - 15);
    self.startBtn.zPosition = 51; 
    [self.bloomNode addChild:self.startBtn];

    self.menuBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.menuBtn.text = @"<";
    self.menuBtn.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    self.menuBtn.fontSize = 36;
    self.menuBtn.position = CGPointMake(20, self.size.height - 40);
    [self.bloomNode addChild:self.menuBtn];

    self.pauseBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.pauseBtn.text = @"⏸";
    self.pauseBtn.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    self.pauseBtn.fontSize = 24;
    self.pauseBtn.position = CGPointMake(self.size.width - 30, self.size.height - 40); 
    [self.bloomNode addChild:self.pauseBtn];
    
    self.musicBtnBg = [SKShapeNode shapeNodeWithCircleOfRadius:16];
    self.musicBtnBg.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    self.musicBtnBg.fillColor = [UIColor clearColor];
    self.musicBtnBg.lineWidth = 2.0;
    self.musicBtnBg.position = CGPointMake(self.size.width - 30, 25);
    [self.bloomNode addChild:self.musicBtnBg];
    
    self.musicBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.musicBtn.text = @"♫";
    self.musicBtn.fontSize = 18;
    self.musicBtn.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter;
    self.musicBtn.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [self.musicBtnBg addChild:self.musicBtn];
    [self updateMusicBtn];
    
    self.highScoreBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.highScoreBtn.text = @"🏆 HIGH SCORES";
    self.highScoreBtn.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    self.highScoreBtn.fontSize = 12;
    self.highScoreBtn.position = CGPointMake(65, 15); 
    [self.bloomNode addChild:self.highScoreBtn];
}

- (void)updateMusicBtn {
    UIColor *onColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    UIColor *offColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];

    if (_musicEnabled) {
        self.musicBtn.fontColor = onColor;
        self.musicBtnBg.strokeColor = onColor;
        if (_synthState && self.gameState == ADSGameStatePlaying) _synthState->playBGM = 1;
    } else {
        self.musicBtn.fontColor = offColor;
        self.musicBtnBg.strokeColor = offColor;
        if (_synthState) _synthState->playBGM = 0;
    }
}

- (void)setupGestures:(SKView *)view {
    NSArray *dirs = @[@(UISwipeGestureRecognizerDirectionUp), @(UISwipeGestureRecognizerDirectionDown), 
                      @(UISwipeGestureRecognizerDirectionLeft), @(UISwipeGestureRecognizerDirectionRight)];
    for (NSNumber *dir in dirs) {
        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
        swipe.direction = dir.integerValue;
        swipe.cancelsTouchesInView = NO; 
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
    _touchStartLoc = [[touches anyObject] locationInNode:self];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint loc = [[touches anyObject] locationInNode:self];
    if (hypot(loc.x - _touchStartLoc.x, loc.y - _touchStartLoc.y) > 15) return;

    if (self.leaderboardNode) {
        SKNode *node = self.leaderboardNode;
        self.leaderboardNode = nil; 
        [node runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.2], [SKAction removeFromParent]]]];
        return;
    }

    if ([self.menuBtn containsPoint:loc]) {
        if (self.exitHandler) self.exitHandler();
        return;
    }
    
    if ([self.musicBtnBg containsPoint:loc]) {
        _musicEnabled = !_musicEnabled;
        [self updateMusicBtn];
        return;
    }
    
    if (!self.highScoreBtn.hidden && [self.highScoreBtn containsPoint:loc]) {
        [self showLeaderboard];
        return;
    }

    if (self.gameState == ADSGameStateMenu) {
        [self resetGame];
    } else if (self.gameState == ADSGameStateDead) {
        [self resetGame];
    } else if (self.gameState == ADSGameStatePlaying) {
        if ([self.pauseBtn containsPoint:loc]) {
            self.gameState = ADSGameStatePaused;
            self.startBtn.text = @"▶ RESUME";
            self.startBtn.hidden = NO;
            self.restartOverlay.hidden = NO;
            if (_synthState) _synthState->playBGM = 0;
        }
    } else if (self.gameState == ADSGameStatePaused) {
        if ([self.startBtn containsPoint:loc] || (!self.restartOverlay.hidden && [self.restartOverlay containsPoint:loc])) {
            self.gameState = ADSGameStatePlaying;
            self.startBtn.hidden = YES;
            self.restartOverlay.hidden = YES;
            if (_synthState && _musicEnabled) _synthState->playBGM = 1;
        }
    }
}

- (void)handleSwipe:(UISwipeGestureRecognizer *)sender {
    if (self.gameState != ADSGameStatePlaying) return;
    
    BOOL changed = NO;
    if (sender.direction == UISwipeGestureRecognizerDirectionUp && self.direction.dy == 0) { self.direction = CGVectorMake(0, 1); changed = YES; }
    else if (sender.direction == UISwipeGestureRecognizerDirectionDown && self.direction.dy == 0) { self.direction = CGVectorMake(0, -1); changed = YES; }
    else if (sender.direction == UISwipeGestureRecognizerDirectionLeft && self.direction.dx == 0) { self.direction = CGVectorMake(-1, 0); changed = YES; }
    else if (sender.direction == UISwipeGestureRecognizerDirectionRight && self.direction.dx == 0) { self.direction = CGVectorMake(1, 0); changed = YES; }
    
    if (changed) {
        UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feed impactOccurred];
    }
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
    self.highScoreBtn.hidden = YES; 
    [self.deathContainer removeFromParent];
    self.deathContainer = nil;
    self.score = 0;
    self.scoreLbl.text = @"SCORE: 0";
    self.direction = CGVectorMake(1, 0);
    self.snake = [NSMutableArray arrayWithObject:[NSValue valueWithCGPoint:CGPointMake([self minX]+2, [self minY]+2)]];
    if (_synthState && _musicEnabled) _synthState->playBGM = 1;
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
    if (currentTime - self.lastTick < 0.16) return;
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
        
        UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
        [feed impactOccurred];
        
        [self playSFX:880.0 dur:0.1];
        
        [self spawnFood];
    } else {
        [self.snake removeLastObject];
    }
    [self render];
}

- (void)die {
    self.gameState = ADSGameStateDead;
    if (_synthState) _synthState->playBGM = 0;
    
    [self playSFX:150.0 dur:0.5];
    
    UINotificationFeedbackGenerator *feed = [[UINotificationFeedbackGenerator alloc] init];
    [feed notificationOccurred:UINotificationFeedbackTypeWarning];
    
    SKShapeNode *flash = [SKShapeNode shapeNodeWithRectOfSize:self.size];
    flash.position = CGPointMake(self.size.width/2, self.size.height/2);
    flash.fillColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.5];
    [self addChild:flash];
    [flash runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.3], [SKAction removeFromParent]]]];
    
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    NSInteger best = [def integerForKey:@"ADS_SnakeHighScore"];
    BOOL isNewHigh = NO;
    if (self.score > best) {
        best = self.score;
        [def setInteger:best forKey:@"ADS_SnakeHighScore"];
        [def synchronize];
        isNewHigh = YES;
    }
    
    self.deathContainer = [SKNode node];
    self.deathContainer.zPosition = 60;
    [self.bloomNode addChild:self.deathContainer];
    
    CGFloat overlayW = self.size.width - 60;
    CGFloat overlayH = (self.size.height - 120) / 2.0;
    SKShapeNode *bg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(overlayW, overlayH) cornerRadius:15];
    bg.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    bg.fillColor = [UIColor colorWithWhite:0.0 alpha:0.9];
    bg.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    bg.lineWidth = 4.0;
    [self.deathContainer addChild:bg];
    
    SKLabelNode *lblScore = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    lblScore.text = isNewHigh ? @"NEW HIGH SCORE!" : [NSString stringWithFormat:@"SCORE: %ld", (long)self.score];
    lblScore.fontColor = isNewHigh ? [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0] : [UIColor whiteColor];
    lblScore.fontSize = isNewHigh ? 20 : 24;
    lblScore.position = CGPointMake(0, 10);
    [bg addChild:lblScore];
    
    SKLabelNode *lblHigh = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    lblHigh.text = [NSString stringWithFormat:@"BEST: %ld", (long)best];
    lblHigh.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    lblHigh.fontSize = 18;
    lblHigh.position = CGPointMake(0, -20);
    [bg addChild:lblHigh];
    
    SKLabelNode *lblIcon = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    lblIcon.text = @"↻";
    lblIcon.fontColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    lblIcon.fontSize = 72;
    lblIcon.position = CGPointMake(-overlayW/2 + 50, -25);
    [bg addChild:lblIcon];
    
    SKLabelNode *lblTap = [SKLabelNode labelNodeWithFontNamed:@"Courier"];
    lblTap.text = @"Tap anywhere to restart";
    lblTap.fontColor = [UIColor grayColor];
    lblTap.fontSize = 12;
    lblTap.position = CGPointMake(0, -overlayH/2 + 15);
    [bg addChild:lblTap];
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


// --- JAILTRIS (TETRIS) SCENE ---
@implementation ADSJailTrisScene {
    NSMutableDictionary *_board; 
    int _bX, _bY, _bType, _bRot, _nextType;
    NSTimeInterval _lastTick, _tickRate;
    NSInteger _score;
    SKNode *_gameLayer;
    SKNode *_previewNode;
    SKNode *_leaderboardNode;
    SKNode *_deathContainer;
    
    SKLabelNode *_scoreLbl;
    SKLabelNode *_highScoreBtn;
    SKLabelNode *_startBtn;
    SKLabelNode *_pauseBtn;
    SKLabelNode *_menuBtn;
    SKLabelNode *_restartBtn;
    SKShapeNode *_restartOverlay;
    
    BOOL _isDead, _isPlaying, _isPaused;
    CGPoint _touchStartLoc;
    
    AVAudioEngine *_audioEngine;
    AVAudioSourceNode *_sourceNode;
    ADSSynthState *_synthState;
    BOOL _musicEnabled;
}

static const CGFloat kRopGrid = 22.0; 
static const int kRopCols = 10;
static const int kRopRows = 20;

static int rop_blocks[7][4][4][2] = {
    { {{-1,0}, {0,0}, {1,0}, {2,0}}, {{0,1}, {0,0}, {0,-1}, {0,-2}}, {{-1,0}, {0,0}, {1,0}, {2,0}}, {{0,1}, {0,0}, {0,-1}, {0,-2}} },
    { {{-1,1}, {-1,0}, {0,0}, {1,0}}, {{1,1}, {0,1}, {0,0}, {0,-1}}, {{1,-1}, {1,0}, {0,0}, {-1,0}}, {{-1,-1}, {0,-1}, {0,0}, {0,1}} },
    { {{1,1}, {-1,0}, {0,0}, {1,0}}, {{1,-1}, {0,1}, {0,0}, {0,-1}}, {{-1,-1}, {1,0}, {0,0}, {-1,0}}, {{-1,1}, {0,-1}, {0,0}, {0,1}} },
    { {{0,1}, {1,1}, {0,0}, {1,0}}, {{0,1}, {1,1}, {0,0}, {1,0}}, {{0,1}, {1,1}, {0,0}, {1,0}}, {{0,1}, {1,1}, {0,0}, {1,0}} },
    { {{0,1}, {1,1}, {-1,0}, {0,0}}, {{0,1}, {0,0}, {1,0}, {1,-1}}, {{0,1}, {1,1}, {-1,0}, {0,0}}, {{0,1}, {0,0}, {1,0}, {1,-1}} },
    { {{0,1}, {-1,0}, {0,0}, {1,0}}, {{0,1}, {0,0}, {1,0}, {0,-1}}, {{-1,0}, {0,0}, {1,0}, {0,-1}}, {{0,1}, {-1,0}, {0,0}, {0,-1}} },
    { {{-1,1}, {0,1}, {0,0}, {1,0}}, {{1,1}, {1,0}, {0,0}, {0,-1}}, {{-1,1}, {0,1}, {0,0}, {1,0}}, {{1,1}, {1,0}, {0,0}, {0,-1}} }
};

- (void)willMoveFromView:(SKView *)view {
    if (_audioEngine) {
        [_audioEngine stop];
        _audioEngine = nil;
    }
    if (_synthState) {
        free(_synthState);
        _synthState = NULL;
    }
    NSArray *gestures = [view.gestureRecognizers copy];
    for (UIGestureRecognizer *g in gestures) {
        [view removeGestureRecognizer:g];
    }
}

- (void)didMoveToView:(SKView *)view {
    self.backgroundColor = [UIColor blackColor];
    _board = [NSMutableDictionary dictionary];
    _tickRate = 0.5;
    
    [self setupAudio];
    
    _gameLayer = [SKNode node];
    CGFloat boardWidth = kRopCols * kRopGrid;
    CGFloat boardHeight = kRopRows * kRopGrid;
    
    _gameLayer.position = CGPointMake((self.size.width - boardWidth)/2.0, (self.size.height - boardHeight)/2.0 + 5);
    [self addChild:_gameLayer];
    
    [self setupUI];
    [self setupGestures:view];
}

- (void)setupAudio {
    _synthState = malloc(sizeof(ADSSynthState));
    memset(_synthState, 0, sizeof(ADSSynthState));
    _musicEnabled = NO;
    _synthState->playBGM = 0;
    
    _audioEngine = [[AVAudioEngine alloc] init];
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:1];
    ADSSynthState *state = _synthState;
    
    _sourceNode = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *ts, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
        float *outBuf = (float *)outputData->mBuffers[0].mData;
        float korobeiniki[] = { 659.25, 493.88, 523.25, 587.33, 523.25, 493.88, 440.0, 440.0, 523.25, 659.25, 587.33, 523.25, 493.88, 493.88, 523.25, 587.33, 659.25, 523.25, 440.0, 440.0, 0, 0, 0, 0 };
        for (AVAudioFrameCount i = 0; i < frameCount; i++) {
            float bgmSamp = 0;
            if (state->playBGM) {
                state->bgmTime += 1.0/44100.0;
                if (state->bgmTime > 0.25) {
                    state->bgmTime = 0;
                    state->bgmIdx = (state->bgmIdx + 1) % 24;
                }
                float bFreq = korobeiniki[state->bgmIdx];
                if (bFreq > 0) {
                    state->bgmPhase += (bFreq * 2.0 * M_PI) / 44100.0;
                    if (state->bgmPhase > 2.0 * M_PI) state->bgmPhase -= 2.0 * M_PI;
                    bgmSamp = (state->bgmPhase < M_PI ? 0.01 : -0.01); 
                }
            }
            float sfxSamp = 0;
            if (state->sfxDur > 0) {
                state->sfxPhase += (state->sfxFreq * 2.0 * M_PI) / 44100.0;
                if (state->sfxPhase > 2.0 * M_PI) state->sfxPhase -= 2.0 * M_PI;
                sfxSamp = (state->sfxPhase < M_PI ? 0.2 : -0.2); 
                state->sfxDur -= 1.0/44100.0;
            }
            outBuf[i] = bgmSamp + sfxSamp;
        }
        return noErr;
    }];
    
    [_audioEngine attachNode:_sourceNode];
    [_audioEngine connect:_sourceNode to:_audioEngine.mainMixerNode format:format];
    [_audioEngine startAndReturnError:nil];
}

- (void)playSFX:(float)freq dur:(float)dur {
    if (_synthState) { _synthState->sfxFreq = freq; _synthState->sfxDur = dur; }
}

- (void)setupUI {
    _scoreLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _scoreLbl.text = @"STACKS CLEARED: 0";
    _scoreLbl.fontSize = 14;
    _scoreLbl.fontColor = [UIColor whiteColor];
    _scoreLbl.position = CGPointMake(self.size.width / 2, 5);
    [self addChild:_scoreLbl];

    _pauseBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _pauseBtn.text = @"⏸";
    _pauseBtn.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _pauseBtn.fontSize = 22;
    _pauseBtn.position = CGPointMake(self.size.width - 25, self.size.height - 35);
    [self addChild:_pauseBtn];

    _menuBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _menuBtn.text = @"<";
    _menuBtn.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    _menuBtn.fontSize = 36;
    _menuBtn.position = CGPointMake(20, self.size.height - 35);
    [self addChild:_menuBtn];
    
    self.musicBtnBg = [SKShapeNode shapeNodeWithCircleOfRadius:16];
    self.musicBtnBg.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    self.musicBtnBg.fillColor = [UIColor clearColor];
    self.musicBtnBg.lineWidth = 2.0;
    self.musicBtnBg.position = CGPointMake(self.size.width - 30, 25);
    [self addChild:self.musicBtnBg];
    
    self.musicBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.musicBtn.text = @"♫";
    self.musicBtn.fontSize = 18;
    self.musicBtn.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter;
    self.musicBtn.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [self.musicBtnBg addChild:self.musicBtn];
    [self updateMusicBtn];
    
    _highScoreBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _highScoreBtn.text = @"🏆 HIGH SCORES";
    _highScoreBtn.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _highScoreBtn.fontSize = 14;
    _highScoreBtn.position = CGPointMake(self.size.width / 2, self.size.height - 15);
    [self addChild:_highScoreBtn];
    
    _previewNode = [SKNode node];
    CGFloat boardWidth = kRopCols * kRopGrid;
    CGFloat boardHeight = kRopRows * kRopGrid;
    _previewNode.position = CGPointMake(_gameLayer.position.x + boardWidth - 42, 
                                        _gameLayer.position.y + boardHeight - 37);
    _previewNode.alpha = 0.5;
    [self addChild:_previewNode];

    CGFloat overlayW = self.size.width - 60;
    CGFloat overlayH = (self.size.height - 120) / 2.0;
    _restartOverlay = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(overlayW, overlayH) cornerRadius:15];
    _restartOverlay.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    _restartOverlay.fillColor = [UIColor colorWithWhite:0.0 alpha:0.8]; 
    _restartOverlay.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _restartOverlay.lineWidth = 4.0;
    _restartOverlay.zPosition = 50;
    _restartOverlay.hidden = YES;
    [self addChild:_restartOverlay];

    _startBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _startBtn.text = @"▶ Start";
    _startBtn.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _startBtn.fontSize = 22;
    _startBtn.position = CGPointMake(self.size.width / 2, self.size.height / 2 - 8);
    _startBtn.zPosition = 51;
    [self addChild:_startBtn];

    _restartBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _restartBtn.text = @"↺";
    _restartBtn.fontColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    _restartBtn.fontSize = 44;
    _restartBtn.position = CGPointMake(20, 15);
    [self addChild:_restartBtn];
}

- (void)updateMusicBtn {
    UIColor *onColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    UIColor *offColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];

    if (_musicEnabled) {
        self.musicBtn.fontColor = onColor;
        self.musicBtnBg.strokeColor = onColor;
        if (_synthState && _isPlaying && !_isPaused && !_isDead) _synthState->playBGM = 1;
    } else {
        self.musicBtn.fontColor = offColor;
        self.musicBtnBg.strokeColor = offColor;
        if (_synthState) _synthState->playBGM = 0;
    }
}

- (void)setupGestures:(SKView *)view {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.cancelsTouchesInView = NO;
    [view addGestureRecognizer:pan];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    tap.cancelsTouchesInView = NO;
    [view addGestureRecognizer:tap];
}

- (void)showLeaderboard {
    if (_leaderboardNode) return;
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    NSInteger best = [def integerForKey:@"ADS_JailTrisHighScore"];
    
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
    [self runAction:[SKAction runBlock:^{ [self playSFX:1046.50 dur:0.4]; }]];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _touchStartLoc = [[touches anyObject] locationInNode:self];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint loc = [[touches anyObject] locationInNode:self];
    if (hypot(loc.x - _touchStartLoc.x, loc.y - _touchStartLoc.y) > 15) return;
    
    if (_leaderboardNode) {
        SKNode *node = _leaderboardNode;
        _leaderboardNode = nil;
        [node runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.2], [SKAction removeFromParent]]]];
        return;
    }

    if ([_menuBtn containsPoint:loc]) {
        if (self.exitHandler) self.exitHandler();
        return;
    }
    
    if ([self.musicBtnBg containsPoint:loc]) {
        _musicEnabled = !_musicEnabled;
        [self updateMusicBtn];
        return;
    }
    
    if (!_highScoreBtn.hidden && [_highScoreBtn containsPoint:loc]) {
        [self showLeaderboard];
        return;
    }

    if ([_restartBtn containsPoint:loc]) {
        [self resetGame];
        return;
    }

    if (_isDead) {
        [self resetGame];
        return;
    }

    if (!_isPlaying) {
        if ([_startBtn containsPoint:loc] || (!_restartOverlay.hidden && [_restartOverlay containsPoint:loc])) {
            [self resetGame];
        }
    } else if (_isPlaying && !_isDead) {
        if ([_pauseBtn containsPoint:loc] || (_isPaused && ([_startBtn containsPoint:loc] || (!_restartOverlay.hidden && [_restartOverlay containsPoint:loc])))) {
            _isPaused = !_isPaused;
            if (_isPaused) {
                _startBtn.text = @"▶ RESUME";
                _startBtn.hidden = NO;
                _restartOverlay.hidden = NO;
                if (_synthState) _synthState->playBGM = 0;
            } else {
                _startBtn.hidden = YES;
                _restartOverlay.hidden = YES;
                if (_synthState && _musicEnabled) _synthState->playBGM = 1;
            }
        }
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)sender {
    if (!_isPlaying || _isDead || _isPaused) return;
    
    CGPoint translation = [sender translationInView:sender.view];
    CGPoint velocity = [sender velocityInView:sender.view];
    
    if (sender.state == UIGestureRecognizerStateEnded) {
        if (fabs(translation.x) > fabs(translation.y)) { 
            int dir = translation.x > 0 ? 1 : -1;
            int blocksToMove = 1;
            
            if (fabs(velocity.x) > 800 || fabs(translation.x) > 60) {
                blocksToMove = 3;
            }
            
            if (blocksToMove > 1) {
                for (int i = 1; i <= blocksToMove; i++) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.025 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if ([self isValidX:self->_bX + dir y:self->_bY rot:self->_bRot type:self->_bType]) {
                            self->_bX += dir;
                            UIImpactFeedbackGenerator *tickFeed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                            [tickFeed impactOccurred];
                            [self render];
                        }
                    });
                }
            } else {
                if ([self isValidX:self->_bX + dir y:self->_bY rot:self->_bRot type:self->_bType]) {
                    self->_bX += dir;
                    UIImpactFeedbackGenerator *tickFeed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                    [tickFeed impactOccurred];
                }
                [self render];
            }
        } else {
            if (translation.y > 20 && velocity.y > 150) { 
                int drops = 0;
                while ([self isValidX:_bX y:_bY - (drops + 1) rot:_bRot type:_bType]) drops++;
                
                if (drops > 0) {
                    int startY = _bY;
                    _bY -= drops;
                    
                    [self playSFX:150.0 dur:0.05];
                    UIImpactFeedbackGenerator *heavyFeed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
                    [heavyFeed impactOccurred];
                    
                    [self render];
                    
                    UIColor *c = [self colorForType:_bType];
                    for (int i = 0; i < 4; i++) {
                        int nx = _bX + rop_blocks[_bType][_bRot][i][0];
                        int nyBot = _bY + rop_blocks[_bType][_bRot][i][1];
                        int nyTop = startY + rop_blocks[_bType][_bRot][i][1];
                        
                        CGFloat height = (nyTop - nyBot) * kRopGrid + (kRopGrid - 1);
                        SKShapeNode *trail = [SKShapeNode shapeNodeWithRect:CGRectMake(0, 0, kRopGrid - 1, height)];
                        trail.position = CGPointMake(self->_gameLayer.position.x + nx * kRopGrid, self->_gameLayer.position.y + nyBot * kRopGrid);
                        trail.fillColor = [c colorWithAlphaComponent:0.25];
                        trail.lineWidth = 0;
                        trail.zPosition = 5;
                        [self addChild:trail];
                        
                        [trail runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.30], [SKAction removeFromParent]]]];
                    }
                    
                    SKAction *sLeft = [SKAction moveByX:-2 y:-1 duration:0.02];
                    SKAction *sRight = [SKAction moveByX:4 y:2 duration:0.02];
                    SKAction *sCenter = [SKAction moveByX:-2 y:-1 duration:0.02];
                    [self->_gameLayer runAction:[SKAction sequence:@[sLeft, sRight, sCenter]]];
                    
                    _lastTick = 0; 
                }
            }
        }
    }
}

- (void)handleTap:(UITapGestureRecognizer *)sender {
    if (!_isPlaying || _isDead || _isPaused) return;
    
    CGPoint viewLoc = [sender locationInView:sender.view];
    CGPoint loc = [self convertPointFromView:viewLoc];
    
    if ([_pauseBtn containsPoint:loc] || [_menuBtn containsPoint:loc] || [self.musicBtnBg containsPoint:loc] || [_restartBtn containsPoint:loc]) {
        return;
    }
    
    if (_bType == 3) return; 
    
    int nextRot = (_bRot + 1) % 4;
    BOOL rotated = NO;
    
    int xOffsets[] = {0, -1, 1, -2, 2};
    for (int i = 0; i < 5; i++) {
        if ([self isValidX:_bX + xOffsets[i] y:_bY rot:nextRot type:_bType]) {
            _bX += xOffsets[i];
            _bRot = nextRot;
            rotated = YES;
            break;
        }
    }
    
    if (!rotated) {
        if ([self isValidX:_bX y:_bY+1 rot:nextRot type:_bType]) {
            _bY++; _bRot = nextRot; rotated = YES;
        } else if ([self isValidX:_bX y:_bY+2 rot:nextRot type:_bType]) {
            _bY += 2; _bRot = nextRot; rotated = YES;
        }
    }
    
    if (rotated) {
        UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feed impactOccurred];
        [self render];
    }
}

- (void)resetGame {
    _isPlaying = YES;
    _isDead = NO;
    _isPaused = NO;
    _startBtn.hidden = YES;
    _restartOverlay.hidden = YES;
    _highScoreBtn.hidden = YES;
    [_deathContainer removeFromParent];
    _deathContainer = nil;
    if (_synthState && _musicEnabled) _synthState->playBGM = 1;
    
    [_board removeAllObjects];
    _score = 0;
    _tickRate = 0.5;
    _scoreLbl.text = @"STACKS CLEARED: 0";
    
    _nextType = arc4random_uniform(7);
    [self spawnBlock];
}

- (void)die {
    _isDead = YES;
    _isPlaying = NO;
    if (_synthState) _synthState->playBGM = 0;
    
    [self runAction:[SKAction sequence:@[
        [SKAction runBlock:^{ [self playSFX:440.0 dur:0.15]; }], [SKAction waitForDuration:0.15],
        [SKAction runBlock:^{ [self playSFX:349.23 dur:0.15]; }], [SKAction waitForDuration:0.15],
        [SKAction runBlock:^{ [self playSFX:293.66 dur:0.4]; }]
    ]]];
    
    UINotificationFeedbackGenerator *feed = [[UINotificationFeedbackGenerator alloc] init];
    [feed notificationOccurred:UINotificationFeedbackTypeError];
    
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    NSInteger best = [def integerForKey:@"ADS_JailTrisHighScore"];
    BOOL isNewHigh = NO;
    if (_score > best) {
        best = _score;
        [def setInteger:best forKey:@"ADS_JailTrisHighScore"];
        [def synchronize];
        isNewHigh = YES;
    }
    
    _deathContainer = [SKNode node];
    _deathContainer.zPosition = 60;
    [self addChild:_deathContainer];
    
    CGFloat overlayW = self.size.width - 60;
    CGFloat overlayH = (self.size.height - 120) / 2.0;
    SKShapeNode *bg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(overlayW, overlayH) cornerRadius:15];
    bg.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    bg.fillColor = [UIColor colorWithWhite:0.0 alpha:0.9];
    bg.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    bg.lineWidth = 4.0;
    [_deathContainer addChild:bg];
    
    SKLabelNode *lblScore = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    lblScore.text = isNewHigh ? @"NEW HIGH SCORE!" : [NSString stringWithFormat:@"SCORE: %ld", (long)_score];
    lblScore.fontColor = isNewHigh ? [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0] : [UIColor whiteColor];
    lblScore.fontSize = isNewHigh ? 20 : 24;
    lblScore.position = CGPointMake(0, 10);
    [bg addChild:lblScore];
    
    SKLabelNode *lblHigh = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    lblHigh.text = [NSString stringWithFormat:@"BEST: %ld", (long)best];
    lblHigh.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    lblHigh.fontSize = 18;
    lblHigh.position = CGPointMake(0, -20);
    [bg addChild:lblHigh];
    
    SKLabelNode *lblIcon = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    lblIcon.text = @"↻";
    lblIcon.fontColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    lblIcon.fontSize = 72;
    lblIcon.position = CGPointMake(-overlayW/2 + 50, -25);
    [bg addChild:lblIcon];
    
    SKLabelNode *lblTap = [SKLabelNode labelNodeWithFontNamed:@"Courier"];
    lblTap.text = @"Tap anywhere to restart";
    lblTap.fontColor = [UIColor grayColor];
    lblTap.fontSize = 12;
    lblTap.position = CGPointMake(0, -overlayH/2 + 15);
    [bg addChild:lblTap];
}

- (void)spawnBlock {
    _bType = _nextType;
    _nextType = arc4random_uniform(7);
    _bRot = 0;
    _bX = (kRopCols / 2) - 1;
    _bY = kRopRows - 2;
    
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
    NSArray *colors = @[
        [UIColor cyanColor], 
        [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1.0], 
        [UIColor orangeColor], 
        [UIColor yellowColor], 
        [UIColor greenColor], 
        [UIColor colorWithRed:0.8 green:0.4 blue:1.0 alpha:1.0], 
        [UIColor redColor]
    ];
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
        
        if (linesCleared == 4) {
            _isPaused = YES;
            
            [self runAction:[SKAction sequence:@[
                [SKAction runBlock:^{ [self playSFX:523.25 dur:0.1]; }], [SKAction waitForDuration:0.12],
                [SKAction runBlock:^{ [self playSFX:659.25 dur:0.1]; }], [SKAction waitForDuration:0.12],
                [SKAction runBlock:^{ [self playSFX:783.99 dur:0.1]; }], [SKAction waitForDuration:0.12],
                [SKAction runBlock:^{ [self playSFX:1046.50 dur:0.3]; }]
            ]]];
            
            SKAction *s1 = [SKAction moveByX:-10 y:10 duration:0.04];
            SKAction *s2 = [SKAction moveByX:20 y:-20 duration:0.04];
            SKAction *s3 = [SKAction moveByX:-20 y:20 duration:0.04];
            SKAction *sCenter = [SKAction moveByX:10 y:-10 duration:0.04];
            [self->_gameLayer runAction:[SKAction sequence:@[s1, s2, s3, sCenter]]];
            
            SKNode *msgContainer = [SKNode node];
            msgContainer.position = CGPointMake(self.size.width/2, self.size.height/2);
            msgContainer.zPosition = 100;
            msgContainer.xScale = 0.1;
            msgContainer.yScale = 0.1;
            [self addChild:msgContainer];
            
            [msgContainer runAction:[SKAction sequence:@[[SKAction scaleTo:1.2 duration:0.2], [SKAction scaleTo:1.0 duration:0.1]]]];
            
            UIColor *gold = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
            
            SKShapeNode *bg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(260, 100) cornerRadius:10];
            bg.fillColor = [UIColor colorWithWhite:0.05 alpha:1.0]; 
            bg.strokeColor = gold;
            bg.lineWidth = 3.0;
            [msgContainer addChild:bg];
            
            SKShapeNode *glow = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(260, 100) cornerRadius:10];
            glow.fillColor = [UIColor clearColor];
            glow.strokeColor = [gold colorWithAlphaComponent:0.8];
            glow.lineWidth = 8.0;
            [msgContainer addChild:glow];
            [glow runAction:[SKAction repeatActionForever:[SKAction sequence:@[[SKAction scaleTo:1.1 duration:0.3], [SKAction fadeAlphaTo:0.2 duration:0.3], [SKAction scaleTo:1.0 duration:0.3], [SKAction fadeAlphaTo:0.8 duration:0.3]]]]];
            
            SKLabelNode *line1 = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
            line1.text = @"[ 4X ROW BONUS! ]";
            line1.fontColor = gold;
            line1.fontSize = 22;
            line1.position = CGPointMake(0, 10);
            [msgContainer addChild:line1];
            
            SKLabelNode *line2 = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
            line2.text = @"100%";
            line2.fontColor = gold;
            line2.fontSize = 34;
            line2.position = CGPointMake(0, -28);
            [msgContainer addChild:line2];
            
            SKShapeNode *flash = [SKShapeNode shapeNodeWithRectOfSize:self.size];
            flash.position = CGPointMake(self.size.width/2, self.size.height/2);
            flash.fillColor = gold;
            flash.alpha = 0.0;
            flash.zPosition = 99;
            [self addChild:flash];
            
            SKAction *strobe = [SKAction sequence:@[[SKAction fadeAlphaTo:0.9 duration:0.05], [SKAction fadeAlphaTo:0.0 duration:0.05], [SKAction fadeAlphaTo:0.7 duration:0.05], [SKAction fadeAlphaTo:0.0 duration:0.05], [SKAction fadeAlphaTo:0.5 duration:0.1], [SKAction fadeOutWithDuration:0.4]]];
            [flash runAction:[SKAction sequence:@[strobe, [SKAction removeFromParent]]]];
            
            SKAction *hold = [SKAction waitForDuration:1.5];
            SKAction *moveUp = [SKAction moveByX:0 y:50 duration:0.6];
            SKAction *fadeOut = [SKAction fadeOutWithDuration:0.6];
            [msgContainer runAction:[SKAction sequence:@[hold, [SKAction group:@[moveUp, fadeOut]], [SKAction removeFromParent], [SKAction runBlock:^{ self->_isPaused = NO; }]]]];
            
            UINotificationFeedbackGenerator *successFeed = [[UINotificationFeedbackGenerator alloc] init];
            [successFeed notificationOccurred:UINotificationFeedbackTypeSuccess];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [successFeed notificationOccurred:UINotificationFeedbackTypeWarning];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [successFeed notificationOccurred:UINotificationFeedbackTypeSuccess];
            });
        } else {
            [self runAction:[SKAction runBlock:^{ [self playSFX:880.0 dur:0.1]; }]];
            
            SKAction *s1 = [SKAction moveByX:-4 y:2 duration:0.04];
            SKAction *s2 = [SKAction moveByX:8 y:-4 duration:0.04];
            SKAction *s3 = [SKAction moveByX:-8 y:4 duration:0.04];
            SKAction *sCenter = [SKAction moveByX:4 y:-2 duration:0.04];
            [self->_gameLayer runAction:[SKAction sequence:@[s1, s2, s3, sCenter]]];
            
            SKAction *colorHighlight = [SKAction runBlock:^{ self->_scoreLbl.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; }];
            SKAction *scaleUp = [SKAction scaleTo:1.5 duration:0.15];
            SKAction *scaleDown = [SKAction scaleTo:1.0 duration:0.15];
            SKAction *colorNormal = [SKAction runBlock:^{ self->_scoreLbl.fontColor = [UIColor whiteColor]; }];
            [self->_scoreLbl runAction:[SKAction sequence:@[colorHighlight, scaleUp, scaleDown, colorNormal]]];
        }
    }
}

- (void)render {
    [_gameLayer removeAllChildren];
    [_previewNode removeAllChildren];
    
    SKShapeNode *border = [SKShapeNode shapeNodeWithRect:CGRectMake(0, 0, kRopCols * kRopGrid, kRopRows * kRopGrid)];
    border.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    border.lineWidth = 2.0;
    [_gameLayer addChild:border];
    
    for (NSString *key in _board) {
        NSArray *comps = [key componentsSeparatedByString:@","];
        int x = [comps[0] intValue], y = [comps[1] intValue];
        SKShapeNode *node = [SKShapeNode shapeNodeWithRect:CGRectMake(x*kRopGrid, y*kRopGrid, kRopGrid-1, kRopGrid-1)];
        node.fillColor = _board[key];
        node.lineWidth = 0;
        [_gameLayer addChild:node];
    }
    
    if (_isPlaying && !_isDead) {
        int ghostY = _bY;
        while ([self isValidX:_bX y:ghostY-1 rot:_bRot type:_bType]) ghostY--;
        
        UIColor *gC = [UIColor colorWithWhite:0.4 alpha:0.50];
        for (int i=0; i<4; i++) {
            int nx = _bX + rop_blocks[_bType][_bRot][i][0];
            int ny = ghostY + rop_blocks[_bType][_bRot][i][1];
            SKShapeNode *node = [SKShapeNode shapeNodeWithRect:CGRectMake(nx*kRopGrid, ny*kRopGrid, kRopGrid-1, kRopGrid-1)];
            node.fillColor = gC;
            node.lineWidth = 0;
            [_gameLayer addChild:node];
        }
        
        UIColor *c = [self colorForType:_bType];
        for (int i=0; i<4; i++) {
            int nx = _bX + rop_blocks[_bType][_bRot][i][0];
            int ny = _bY + rop_blocks[_bType][_bRot][i][1];
            SKShapeNode *node = [SKShapeNode shapeNodeWithRect:CGRectMake(nx*kRopGrid, ny*kRopGrid, kRopGrid-1, kRopGrid-1)];
            node.fillColor = c;
            node.lineWidth = 0;
            [_gameLayer addChild:node];
        }
        
        UIColor *nc = [self colorForType:_nextType];
        CGFloat pGrid = 14.0; 
        for (int i=0; i<4; i++) {
            int nx = rop_blocks[_nextType][0][i][0];
            int ny = rop_blocks[_nextType][0][i][1];
            SKShapeNode *nNode = [SKShapeNode shapeNodeWithRect:CGRectMake(nx*pGrid, ny*pGrid, pGrid-1, pGrid-1)];
            nNode.fillColor = nc;
            nNode.lineWidth = 0;
            [_previewNode addChild:nNode];
        }
    }
}

@end

// --- MENU SCENE ---
@implementation ADSGameMenuScene {
    SKLabelNode *_closeBtn;
    SKShapeNode *_btnSnake;
    SKShapeNode *_btnTetris;
    SKLabelNode *_dedicationBtn;
}

- (void)didMoveToView:(SKView *)view {
    self.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    
    SKLabelNode *title = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    title.text = @"SELECT GAME";
    title.fontColor = [UIColor whiteColor];
    title.fontSize = 22;
    title.position = CGPointMake(self.size.width/2, self.size.height - 78); 
    [self addChild:title];
    
    _closeBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _closeBtn.text = @"❌";
    _closeBtn.fontSize = 20;
    _closeBtn.position = CGPointMake(self.size.width - 30, self.size.height - 40);
    [self addChild:_closeBtn];

    _btnSnake = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(200, 80) cornerRadius:12];
    _btnSnake.position = CGPointMake(self.size.width/2, self.size.height/2 - 28);
    _btnSnake.fillColor = [UIColor clearColor];
    _btnSnake.strokeColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    _btnSnake.lineWidth = 3.0;
    [self addChild:_btnSnake];
    
    SKLabelNode *snakeLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    snakeLbl.text = @"🐍 PYEATER";
    snakeLbl.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    snakeLbl.fontSize = 18;
    snakeLbl.position = CGPointMake(0, -6);
    [_btnSnake addChild:snakeLbl];

    _btnTetris = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(200, 80) cornerRadius:12];
    _btnTetris.position = CGPointMake(self.size.width/2, self.size.height/2 + 72);
    _btnTetris.fillColor = [UIColor clearColor];
    _btnTetris.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _btnTetris.lineWidth = 3.0;
    [self addChild:_btnTetris];
    
    SKLabelNode *tetrisLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    tetrisLbl.text = @"🧱 JAILTRIS";
    tetrisLbl.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    tetrisLbl.fontSize = 18;
    tetrisLbl.position = CGPointMake(0, -6);
    [_btnTetris addChild:tetrisLbl];

    _dedicationBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _dedicationBtn.text = @"DEDICATED TO ⚫ ANDREW ";
    _dedicationBtn.fontColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    _dedicationBtn.fontSize = 16;
    _dedicationBtn.position = CGPointMake(self.size.width/2, 74);
    [self addChild:_dedicationBtn];
    
    SKShapeNode *glow = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(260, 30) cornerRadius:15];
    glow.position = CGPointMake(0, 6);
    glow.fillColor = [UIColor colorWithRed:0.0 green:0.2 blue:0.8 alpha:0.6];
    glow.lineWidth = 0;
    glow.zPosition = -1;
    [_dedicationBtn addChild:glow];
    
    SKAction *pulseIn = [SKAction group:@[[SKAction scaleTo:0.95 duration:2.0], [SKAction fadeAlphaTo:0.2 duration:2.0]]];
    SKAction *pulseOut = [SKAction group:@[[SKAction scaleTo:1.05 duration:2.0], [SKAction fadeAlphaTo:0.8 duration:2.0]]];
    [glow runAction:[SKAction repeatActionForever:[SKAction sequence:@[pulseIn, pulseOut]]]];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint loc = [[touches anyObject] locationInNode:self];
    
    if ([_closeBtn containsPoint:loc]) {
        if (self.exitHandler) self.exitHandler();
        return;
    }
    
    if ([_dedicationBtn containsPoint:loc]) {
        NSURL *url = [NSURL URLWithString:@"https://github.com/00000000aaaaaaaa"];
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
        return;
    }
    
    if ([_btnSnake containsPoint:loc]) {
        if (self.onSelectGame) self.onSelectGame(0);
    } else if ([_btnTetris containsPoint:loc]) {
        if (self.onSelectGame) self.onSelectGame(1);
    }
}
@end

// --- CREDITS CONTROLLER ---
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

- (void)showMenuScene:(BOOL)animate {
    if (!self.gameView) return;
    ADSGameMenuScene *menuScene = [[ADSGameMenuScene alloc] initWithSize:self.gameView.bounds.size];
    menuScene.scaleMode = SKSceneScaleModeAspectFill;
    __weak typeof(self) weakSelf = self;
    menuScene.exitHandler = ^{ [weakSelf teardownGame]; };
    
    menuScene.onSelectGame = ^(NSInteger gameIndex) {
        SKScene *selectedScene;
        if (gameIndex == 0) {
            ADSPyEaterScene *s = [[ADSPyEaterScene alloc] initWithSize:weakSelf.gameView.bounds.size];
            s.exitHandler = ^{ [weakSelf showMenuScene:YES]; };
            selectedScene = s;
        } else {
            ADSJailTrisScene *s = [[ADSJailTrisScene alloc] initWithSize:weakSelf.gameView.bounds.size];
            s.exitHandler = ^{ [weakSelf showMenuScene:YES]; };
            selectedScene = s;
        }
        selectedScene.scaleMode = SKSceneScaleModeAspectFill;
        SKTransition *transition = [SKTransition pushWithDirection:SKTransitionDirectionLeft duration:0.3];
        [weakSelf.gameView presentScene:selectedScene transition:transition];
    };
    
    if (animate) {
        SKTransition *transition = [SKTransition pushWithDirection:SKTransitionDirectionRight duration:0.3];
        [self.gameView presentScene:menuScene transition:transition];
    } else {
        [self.gameView presentScene:menuScene];
    }
}

- (void)launchGame {
    if (self.gameView) return;
    
    UITableView *table = (UITableView *)[self valueForKey:@"_table"];
    if (!table) return;

    CGFloat width = table.bounds.size.width;
    CGFloat height = 480.0; 
    
    UIView *footerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height + 40)];
    footerContainer.backgroundColor = [UIColor clearColor];
    
    self.gameView = [[SKView alloc] initWithFrame:CGRectMake(16, 20, width - 32, height)];
    self.gameView.layer.cornerRadius = 12.0;
    self.gameView.clipsToBounds = YES;
    self.gameView.alpha = 0.0;
    
    [footerContainer addSubview:self.gameView];
    table.tableFooterView = footerContainer;
    
    [self showMenuScene:NO];
    
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