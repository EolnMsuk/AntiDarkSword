#import "ADSGames.h"
#import <AVFoundation/AVFoundation.h>

@interface ADSPyEaterScene ()
@property (nonatomic, strong) SKLabelNode *musicBtn;
@property (nonatomic, strong) SKShapeNode *musicBtnBg;
@property (nonatomic, strong) SKNode *deathContainer;
@end

@implementation ADSPyEaterScene {
    CGPoint _touchStartLoc;
    AVAudioEngine *_audioEngine;
    AVAudioSourceNode *_sourceNode;
    ADSSynthState *_synthState;
    BOOL _musicEnabled;
    SKShapeNode *_menuBg;
    SKShapeNode *_pauseBg;
    BOOL _hasSurpassedHighScore;
    NSInteger _savedHighScore;
    SKNode *_foodLayer;
}
static const CGFloat kGridSize = 20.0;

- (int)minX { return 2; }
- (int)maxX { return (self.size.width / kGridSize) - 2; }
- (int)minY { return 4; } 
- (int)maxY { return (self.size.height / kGridSize) - 3; } 

- (void)willMoveFromView:(SKView *)view {
    if (_audioEngine) { [_audioEngine stop]; _audioEngine = nil; }
    _sourceNode = nil;
    if (_synthState) { free(_synthState); _synthState = NULL; }
    NSArray *gestures = [view.gestureRecognizers copy];
    for (UIGestureRecognizer *g in gestures) { [view removeGestureRecognizer:g]; }
}

- (void)didMoveToView:(SKView *)view {
    self.backgroundColor = [UIColor blackColor];
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    _savedHighScore = [def integerForKey:@"ADS_SnakeHighScore"];
    
    self.bloomNode = [[SKEffectNode alloc] init];
    CIFilter *bloom = [CIFilter filterWithName:@"CIBloom"];
    [bloom setValue:@0.8 forKey:@"inputRadius"];
    [bloom setValue:@1.5 forKey:@"inputIntensity"];
    self.bloomNode.filter = bloom;
    self.bloomNode.shouldEnableEffects = YES;
    [self addChild:self.bloomNode];
    
    _foodLayer = [SKNode node];
    [self.bloomNode addChild:_foodLayer];
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
        float mel[]  = { 659.25f,783.99f,880.00f,783.99f,659.25f,523.25f,587.33f,659.25f,
                         587.33f,523.25f,440.00f,493.88f,523.25f,587.33f,659.25f,0 };
        float bass[] = { 329.63f,391.99f,440.00f,391.99f,329.63f,261.63f,293.66f,329.63f,
                         293.66f,261.63f,220.00f,246.94f,261.63f,293.66f,329.63f,0 };
        const float sr = 44100.0f, tp = 2.0f*(float)M_PI;
        for (AVAudioFrameCount i = 0; i < frameCount; i++) {
            float bgmSamp = 0, arpSamp = 0;
            if (state->playBGM) {
                state->bgmTime += 1.0f/sr;
                if (state->bgmTime > 0.12f) { state->bgmTime = 0; state->bgmIdx = (state->bgmIdx + 1) % 16; }
                float mF = mel[state->bgmIdx], bF = bass[state->bgmIdx];
                if (mF > 0) {
                    state->bgmPhase += (mF * tp) / sr;
                    if (state->bgmPhase > tp) state->bgmPhase -= tp;
                    float t = state->bgmPhase / tp;
                    bgmSamp = (t < 0.5f ? 4.0f*t - 1.0f : 3.0f - 4.0f*t) * 0.026f;
                    state->bgmPhase2 += (bF * tp) / sr;
                    if (state->bgmPhase2 > tp) state->bgmPhase2 -= tp;
                    bgmSamp += (state->bgmPhase2 < (float)M_PI ? 0.011f : -0.011f);
                    state->bgmTime2 += 1.0f/sr;
                    if (state->bgmTime2 > 0.06f) { state->bgmTime2 = 0; state->bgmIdx2 = (state->bgmIdx2 + 1) & 3; }
                    static const float arpM[] = {1.0f, 1.498f, 2.0f, 1.498f};
                    float aF = mF * arpM[state->bgmIdx2];
                    state->bgmPhase3 += (aF * tp) / sr;
                    if (state->bgmPhase3 > tp) state->bgmPhase3 -= tp;
                    arpSamp = (state->bgmPhase3 < (float)(M_PI * 0.25f) ? 0.006f : -0.006f);
                }
            }
            float sfxSamp = 0;
            if (state->sfxDur > 0) {
                state->sfxFreq += state->sfxSweepRate / sr;
                if (state->sfxFreq < 20.0f) state->sfxFreq = 20.0f;
                state->sfxPhase += (state->sfxFreq * tp) / sr;
                if (state->sfxPhase > tp) state->sfxPhase -= tp;
                float env = (state->sfxEnvInit > 0) ? (state->sfxDur / state->sfxEnvInit) : 1.0f;
                sfxSamp = (state->sfxPhase < (float)M_PI ? 1.0f : -1.0f) * 0.22f * env;
                state->sfxDur -= 1.0f/sr;
            }
            if (state->sfxDur2 > 0) {
                state->sfxFreq2 += state->sfxSweep2Rate / sr;
                if (state->sfxFreq2 < 20.0f) state->sfxFreq2 = 20.0f;
                state->sfxPhase2 += (state->sfxFreq2 * tp) / sr;
                if (state->sfxPhase2 > tp) state->sfxPhase2 -= tp;
                float env2 = (state->sfxEnvInit > 0) ? (state->sfxDur2 / state->sfxEnvInit) : 1.0f;
                sfxSamp += (state->sfxPhase2 < (float)M_PI ? 1.0f : -1.0f) * 0.12f * env2;
                state->sfxDur2 -= 1.0f/sr;
            }
            outBuf[i] = bgmSamp + arpSamp + sfxSamp;
        }
        return noErr;
    }];
    
    [_audioEngine attachNode:_sourceNode];
    [_audioEngine connect:_sourceNode to:_audioEngine.mainMixerNode format:format];
    [_audioEngine startAndReturnError:nil];
}

- (void)playSFX:(float)freq dur:(float)dur {
    if (!_synthState) return;
    _synthState->sfxFreq = freq; _synthState->sfxDur = dur; _synthState->sfxEnvInit = dur;
    _synthState->sfxPhase = 0; _synthState->sfxDur2 = 0;
    _synthState->sfxSweepRate = 0; _synthState->sfxSweep2Rate = 0;
}
- (void)playSFX2:(float)f1 freq2:(float)f2 dur:(float)dur {
    if (!_synthState) return;
    _synthState->sfxFreq = f1; _synthState->sfxFreq2 = f2;
    _synthState->sfxDur = dur; _synthState->sfxDur2 = dur; _synthState->sfxEnvInit = dur;
    _synthState->sfxPhase = 0; _synthState->sfxPhase2 = 0;
    _synthState->sfxSweepRate = 0; _synthState->sfxSweep2Rate = 0;
}
- (void)playSFXSweep:(float)freq sweep:(float)sweep dur:(float)dur {
    if (!_synthState) return;
    _synthState->sfxFreq = freq; _synthState->sfxDur = dur; _synthState->sfxEnvInit = dur;
    _synthState->sfxPhase = 0; _synthState->sfxDur2 = 0;
    _synthState->sfxSweepRate = sweep; _synthState->sfxSweep2Rate = 0;
}
- (void)playSFX2Sweep:(float)f1 freq2:(float)f2 sweep1:(float)s1 sweep2:(float)s2 dur:(float)dur {
    if (!_synthState) return;
    _synthState->sfxFreq = f1; _synthState->sfxFreq2 = f2;
    _synthState->sfxDur = dur; _synthState->sfxDur2 = dur; _synthState->sfxEnvInit = dur;
    _synthState->sfxPhase = 0; _synthState->sfxPhase2 = 0;
    _synthState->sfxSweepRate = s1; _synthState->sfxSweep2Rate = s2;
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

    _menuBg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(44, 44) cornerRadius:8];
    _menuBg.strokeColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    _menuBg.fillColor = [UIColor clearColor];
    _menuBg.position = CGPointMake(32, self.size.height - 23);
    [self.bloomNode addChild:_menuBg];

    self.menuBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.menuBtn.text = @"<";
    self.menuBtn.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    self.menuBtn.fontSize = 24;
    self.menuBtn.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter;
    self.menuBtn.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [_menuBg addChild:self.menuBtn];

    _pauseBg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(44, 44) cornerRadius:8];
    _pauseBg.strokeColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    _pauseBg.fillColor = [UIColor clearColor];
    _pauseBg.position = CGPointMake(self.size.width - 32, self.size.height - 23);
    [self.bloomNode addChild:_pauseBg];

    self.pauseBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.pauseBtn.text = @"||";
    self.pauseBtn.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    self.pauseBtn.fontSize = 22;
    self.pauseBtn.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter;
    self.pauseBtn.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [_pauseBg addChild:self.pauseBtn];
    
    self.musicBtnBg = [SKShapeNode shapeNodeWithCircleOfRadius:16];
    self.musicBtnBg.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    self.musicBtnBg.fillColor = [UIColor clearColor];
    self.musicBtnBg.lineWidth = 2.0;
    self.musicBtnBg.position = CGPointMake(self.size.width - 41, 28);
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
    self.highScoreBtn.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    self.highScoreBtn.fontSize = 12;
    self.highScoreBtn.position = CGPointMake(95, 24);
    self.highScoreBtn.hidden = NO;
    
    SKShapeNode *hsBorder = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(140, 28) cornerRadius:14];
    hsBorder.strokeColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    hsBorder.fillColor = [UIColor clearColor];
    hsBorder.lineWidth = 2.0;
    hsBorder.position = CGPointMake(0, 4);
    [self.highScoreBtn addChild:hsBorder];
    
    [self.bloomNode addChild:self.highScoreBtn];
}

- (void)updateMusicBtn {
    UIColor *onColor = [UIColor cyanColor];
    UIColor *offColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    if (_musicEnabled) {
        self.musicBtn.fontColor = onColor; self.musicBtnBg.strokeColor = onColor;
        if (_synthState && self.gameState == ADSGameStatePlaying) _synthState->playBGM = 1;
    } else {
        self.musicBtn.fontColor = offColor; self.musicBtnBg.strokeColor = offColor;
        if (_synthState) _synthState->playBGM = 0;
    }
}

- (void)setupGestures:(SKView *)view {
    NSArray *dirs = @[@(UISwipeGestureRecognizerDirectionUp), @(UISwipeGestureRecognizerDirectionDown), 
                      @(UISwipeGestureRecognizerDirectionLeft), @(UISwipeGestureRecognizerDirectionRight)];
    for (NSNumber *dir in dirs) {
        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
        swipe.direction = dir.integerValue; swipe.cancelsTouchesInView = NO; [view addGestureRecognizer:swipe];
    }
}

- (void)showLeaderboard {
    if (self.leaderboardNode) return;
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    NSInteger best = [def integerForKey:@"ADS_SnakeHighScore"];
    
    self.leaderboardNode = [SKNode node];
    self.leaderboardNode.zPosition = 100; self.leaderboardNode.alpha = 0;
    
    SKShapeNode *blocker = [SKShapeNode shapeNodeWithRectOfSize:self.size];
    blocker.position = CGPointMake(self.size.width/2, self.size.height/2);
    blocker.fillColor = [UIColor clearColor]; blocker.strokeColor = [UIColor clearColor];
    [self.leaderboardNode addChild:blocker];
    
    SKShapeNode *bg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(220, 140) cornerRadius:12];
    bg.fillColor = [UIColor colorWithWhite:0.1 alpha:0.95]; bg.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    bg.lineWidth = 2.0; bg.position = CGPointMake(self.size.width/2, self.size.height/2);
    [self.leaderboardNode addChild:bg];
    
    SKLabelNode *title = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    title.text = @"HIGH SCORE"; title.fontColor = [UIColor whiteColor];
    title.fontSize = 22; title.position = CGPointMake(0, 25); [bg addChild:title];
    
    SKLabelNode *val = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    val.text = [NSString stringWithFormat:@"%ld", (long)best]; val.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    val.fontSize = 36; val.position = CGPointMake(0, -15); [bg addChild:val];
    
    SKLabelNode *tap = [SKLabelNode labelNodeWithFontNamed:@"Courier"];
    tap.text = @"Tap anywhere to close"; tap.fontColor = [UIColor grayColor];
    tap.fontSize = 12; tap.position = CGPointMake(0, -50); [bg addChild:tap];
    
    [self.bloomNode addChild:self.leaderboardNode];
    [self.leaderboardNode runAction:[SKAction fadeInWithDuration:0.2]];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { _touchStartLoc = [[touches anyObject] locationInNode:self]; }

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint loc = [[touches anyObject] locationInNode:self];
    if (hypot(loc.x - _touchStartLoc.x, loc.y - _touchStartLoc.y) > 15) return;

    void (^playTap)(void) = ^{
        UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feed impactOccurred];
    };

    if (self.leaderboardNode) {
        playTap(); SKNode *node = self.leaderboardNode; self.leaderboardNode = nil; 
        [node runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.2], [SKAction removeFromParent]]]];
        return;
    }
    if ([_menuBg containsPoint:loc]) { playTap(); [self playSFX:440.0 dur:0.08]; if (self.exitHandler) self.exitHandler(); return; }
    if ([self.musicBtnBg containsPoint:loc]) { playTap(); [self playSFX2:523.25 freq2:659.25 dur:0.1]; _musicEnabled = !_musicEnabled; [self updateMusicBtn]; return; }
    if ([self.highScoreBtn containsPoint:loc]) {
        playTap();
        if (self.gameState == ADSGameStatePlaying) {
            self.gameState = ADSGameStatePaused; self.startBtn.text = @"▶ RESUME";
            self.startBtn.hidden = NO; self.restartOverlay.hidden = NO;
            if (_synthState) _synthState->playBGM = 0;
        }
        [self playSFX2:1046.50 freq2:1318.51 dur:0.4]; [self showLeaderboard]; return;
    }

    if (self.gameState == ADSGameStateMenu) {
        playTap(); [self playSFX2:880.0 freq2:1108.73 dur:0.1]; [self resetGame];
    } else if (self.gameState == ADSGameStateDead) {
        playTap(); [self playSFXSweep:440.0 sweep:440.0 dur:0.15]; [self resetGame];
    } else if (self.gameState == ADSGameStatePlaying) {
        if ([_pauseBg containsPoint:loc]) {
            playTap(); [self playSFX2:330.0 freq2:220.0 dur:0.1]; self.gameState = ADSGameStatePaused; self.startBtn.text = @"▶ RESUME";
            self.startBtn.hidden = NO; self.restartOverlay.hidden = NO;
            if (_synthState) _synthState->playBGM = 0;
        }
    } else if (self.gameState == ADSGameStatePaused) {
        if ([self.startBtn containsPoint:loc] || (!self.restartOverlay.hidden && [self.restartOverlay containsPoint:loc])) {
            playTap(); [self playSFX2:880.0 freq2:1108.73 dur:0.1]; self.gameState = ADSGameStatePlaying; self.startBtn.hidden = YES; self.restartOverlay.hidden = YES;
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
    
    if (changed) { UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [feed impactOccurred]; [self playSFX:150.0 dur:0.05]; }
}

- (void)drawWalls {
    self.gameLayer.position = CGPointMake(0, -4); 
    CGFloat w = ([self maxX] - [self minX] + 1) * kGridSize;
    CGFloat h = ([self maxY] - [self minY] + 1) * kGridSize;
    SKShapeNode *border = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(w + 2, h + 2)];
    border.position = CGPointMake(([self minX] + [self maxX])/2.0 * kGridSize, (([self minY] + [self maxY])/2.0 * kGridSize) - 4);
    border.strokeColor = [UIColor colorWithRed:0.2 green:0.2 blue:1.0 alpha:1.0];
    border.lineWidth = 4.0;
    [self.bloomNode addChild:border];
}

- (void)resetGame {
    self.gameState = ADSGameStatePlaying;
    self.startBtn.hidden = YES; self.restartOverlay.hidden = YES;
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    _savedHighScore = [def integerForKey:@"ADS_SnakeHighScore"];
    _hasSurpassedHighScore = NO;
    [self.deathContainer removeFromParent]; self.deathContainer = nil;
    self.score = 0; self.scoreLbl.text = @"SCORE: 0";
    self.direction = CGVectorMake(1, 0);
    self.snake = [NSMutableArray arrayWithObject:[NSValue valueWithCGPoint:CGPointMake([self minX]+2, [self minY]+2)]];
    if (_synthState && _musicEnabled) _synthState->playBGM = 1;
    [self spawnFood]; self.lastTick = 0;
}

- (void)spawnFood {
    if ([self maxX] <= [self minX] || [self maxY] <= [self minY]) return;
    BOOL valid = NO; int x = 0, y = 0;
    while (!valid) {
        x = [self minX] + arc4random_uniform([self maxX] - [self minX] + 1);
        y = [self minY] + arc4random_uniform([self maxY] - [self minY] + 1);
        valid = YES;
        CGPoint testPoint = CGPointMake(x, y);
        for (NSValue *val in self.snake) { if (CGPointEqualToPoint(val.CGPointValue, testPoint)) { valid = NO; break; } }
    }
    self.food = CGPointMake(x, y);
    [self updateFoodNode];
}

- (void)updateFoodNode {
    [_foodLayer removeAllChildren];
    SKShapeNode *fNode = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(kGridSize-2, kGridSize-2)];
    fNode.fillColor = [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:1.0];
    fNode.lineWidth = 0;
    fNode.position = CGPointMake(self.food.x * kGridSize + self.gameLayer.position.x, self.food.y * kGridSize + self.gameLayer.position.y);
    [fNode runAction:[SKAction repeatActionForever:[SKAction sequence:@[[SKAction scaleTo:1.25 duration:0.25], [SKAction scaleTo:0.8 duration:0.25]]]]];
    [_foodLayer addChild:fNode];
}

- (void)update:(NSTimeInterval)currentTime {
    if (self.gameState != ADSGameStatePlaying) return;
    if (currentTime - self.lastTick < 0.16) return;
    self.lastTick = currentTime;
    
    CGPoint head = self.snake.firstObject.CGPointValue;
    CGPoint next = CGPointMake(head.x + self.direction.dx, head.y + self.direction.dy);
    if (next.x < [self minX] || next.x > [self maxX] || next.y < [self minY] || next.y > [self maxY]) { [self die]; return; }
    for (NSValue *val in self.snake) { if (CGPointEqualToPoint(val.CGPointValue, next)) { [self die]; return; } }
    
    [self.snake insertObject:[NSValue valueWithCGPoint:next] atIndex:0];
    
    if (CGPointEqualToPoint(next, self.food)) {
        self.score += 10; self.scoreLbl.text = [NSString stringWithFormat:@"SCORE: %ld", (long)self.score];
        if (!_hasSurpassedHighScore && self.score > _savedHighScore && _savedHighScore > 0) {
            _hasSurpassedHighScore = YES;
            [self runAction:[SKAction sequence:@[
                [SKAction runBlock:^{ [self playSFX2:987.77 freq2:1975.54 dur:0.1]; }],
                [SKAction waitForDuration:0.1],
                [SKAction runBlock:^{ [self playSFX2:1318.51 freq2:1975.54 dur:0.22]; }]
            ]]];
            SKLabelNode *bestLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
            bestLbl.text = @"🏆 NEW BEST!"; bestLbl.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
            bestLbl.fontSize = 18; bestLbl.position = CGPointMake(self.size.width/2, self.size.height - 65);
            bestLbl.zPosition = 200; bestLbl.alpha = 0; [self.bloomNode addChild:bestLbl];
            [bestLbl runAction:[SKAction sequence:@[
                [SKAction group:@[[SKAction fadeInWithDuration:0.12], [SKAction moveByX:0 y:8 duration:0.12]]],
                [SKAction waitForDuration:0.7],
                [SKAction group:@[[SKAction fadeOutWithDuration:0.3], [SKAction moveByX:0 y:22 duration:0.3]]],
                [SKAction removeFromParent]
            ]]];
        } else { [self playSFX2:880.0 freq2:1760.0 dur:0.13]; }
        UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
        [feed impactOccurred];
        CGFloat py = next.y * kGridSize + self.gameLayer.position.y;
        SKShapeNode *pulse = [SKShapeNode shapeNodeWithCircleOfRadius:kGridSize * 0.7f];
        pulse.position = CGPointMake(next.x * kGridSize, py);
        pulse.strokeColor = [UIColor colorWithRed:0.3 green:1.0 blue:0.8 alpha:0.9];
        pulse.fillColor = [UIColor clearColor]; pulse.lineWidth = 2.5; pulse.zPosition = 20;
        [self.bloomNode addChild:pulse];
        [pulse runAction:[SKAction sequence:@[[SKAction group:@[[SKAction scaleTo:2.8 duration:0.22], [SKAction fadeOutWithDuration:0.22]]], [SKAction removeFromParent]]]];
        [self spawnFood];
        SKShapeNode *growPulse = [SKShapeNode shapeNodeWithCircleOfRadius:kGridSize * 0.65f];
        growPulse.position = CGPointMake(next.x * kGridSize + self.gameLayer.position.x, next.y * kGridSize + self.gameLayer.position.y);
        growPulse.fillColor = [UIColor colorWithRed:0.4 green:1.0 blue:1.0 alpha:0.85];
        growPulse.strokeColor = [UIColor clearColor]; growPulse.lineWidth = 0; growPulse.zPosition = 25;
        [self.bloomNode addChild:growPulse];
        [growPulse runAction:[SKAction sequence:@[
            [SKAction group:@[[SKAction scaleTo:2.2 duration:0.12], [SKAction fadeAlphaTo:0.0 duration:0.12]]],
            [SKAction removeFromParent]
        ]]];
    } else { [self.snake removeLastObject]; }
    [self render];
}

- (void)die {
    self.gameState = ADSGameStateDead;
    if (_synthState) _synthState->playBGM = 0;
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    NSInteger best = [def integerForKey:@"ADS_SnakeHighScore"];
    BOOL isNewHigh = NO;
    if (self.score > best) { best = self.score; [def setInteger:best forKey:@"ADS_SnakeHighScore"]; [def synchronize]; isNewHigh = YES; }
    
    if (isNewHigh && self.score > 0) {
        [self runAction:[SKAction sequence:@[
            [SKAction runBlock:^{ [self playSFX2:523.25 freq2:1046.50 dur:0.1]; }], [SKAction waitForDuration:0.12],
            [SKAction runBlock:^{ [self playSFX2:659.25 freq2:1318.51 dur:0.1]; }], [SKAction waitForDuration:0.12],
            [SKAction runBlock:^{ [self playSFX2:783.99 freq2:1567.98 dur:0.1]; }], [SKAction waitForDuration:0.12],
            [SKAction runBlock:^{ [self playSFX2:1046.50 freq2:1567.98 dur:0.45]; }]
        ]]];
    } else { [self playSFX2Sweep:320.0 freq2:160.0 sweep1:-420.0 sweep2:-210.0 dur:0.6]; }

    UINotificationFeedbackGenerator *feed = [[UINotificationFeedbackGenerator alloc] init];
    [feed notificationOccurred:UINotificationFeedbackTypeWarning];

    SKShapeNode *flash = [SKShapeNode shapeNodeWithRectOfSize:self.size];
    flash.position = CGPointMake(self.size.width/2, self.size.height/2);
    flash.fillColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.6]; flash.zPosition = 99;
    [self addChild:flash];
    [flash runAction:[SKAction sequence:@[
        [SKAction fadeAlphaTo:0.7 duration:0.04], [SKAction fadeAlphaTo:0.1 duration:0.07],
        [SKAction fadeAlphaTo:0.5 duration:0.04], [SKAction fadeAlphaTo:0.0 duration:0.18],
        [SKAction removeFromParent]
    ]]];
    SKShapeNode *wave = [SKShapeNode shapeNodeWithCircleOfRadius:12];
    wave.position = CGPointMake(self.snake.firstObject.CGPointValue.x * kGridSize + self.gameLayer.position.x,
                                self.snake.firstObject.CGPointValue.y * kGridSize + self.gameLayer.position.y);
    wave.strokeColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0]; wave.fillColor = [UIColor clearColor];
    wave.lineWidth = 3.0; wave.zPosition = 90; [self.bloomNode addChild:wave];
    [wave runAction:[SKAction sequence:@[[SKAction group:@[[SKAction scaleTo:5.5 duration:0.35], [SKAction fadeOutWithDuration:0.35]]], [SKAction removeFromParent]]]];
    
    CGPoint origLayerPos = self.gameLayer.position;
    SKAction *gsh1 = [SKAction moveByX:-8 y:5 duration:0.04]; SKAction *gsh2 = [SKAction moveByX:16 y:-10 duration:0.04];
    SKAction *gsh3 = [SKAction moveByX:-16 y:10 duration:0.04]; SKAction *gsh4 = [SKAction moveByX:8 y:-5 duration:0.04];
    SKAction *gshR = [SKAction moveTo:origLayerPos duration:0.03];
    [self.gameLayer runAction:[SKAction sequence:@[gsh1, gsh2, gsh3, gsh4, gshR]]];
    self.deathContainer = [SKNode node]; self.deathContainer.zPosition = 60; [self.bloomNode addChild:self.deathContainer];
    CGFloat overlayW = self.size.width - 60; CGFloat overlayH = (self.size.height - 120) / 2.0;
    SKShapeNode *bg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(overlayW, overlayH) cornerRadius:15];
    bg.position = CGPointMake((self.size.width / 2) - 1, self.size.height / 2);
    bg.fillColor = [UIColor colorWithWhite:0.0 alpha:0.9]; bg.strokeColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0]; bg.lineWidth = 4.0;
    [self.deathContainer addChild:bg];
    
    if (isNewHigh) {
        SKLabelNode *lblTitle = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
        lblTitle.text = @"NEW HIGH SCORE!"; lblTitle.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
        lblTitle.fontSize = 20; lblTitle.position = CGPointMake(0, 15); [bg addChild:lblTitle];
        SKLabelNode *lblScore = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
        lblScore.text = [NSString stringWithFormat:@"%ld", (long)self.score]; lblScore.fontColor = [UIColor whiteColor];
        lblScore.fontSize = 28; lblScore.position = CGPointMake(0, -15); [bg addChild:lblScore];
    } else {
        SKLabelNode *lblScore = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
        lblScore.text = [NSString stringWithFormat:@"SCORE: %ld", (long)self.score]; lblScore.fontColor = [UIColor whiteColor];
        lblScore.fontSize = 24; lblScore.position = CGPointMake(0, 10); [bg addChild:lblScore];
        SKLabelNode *lblHigh = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
        lblHigh.text = [NSString stringWithFormat:@"BEST: %ld", (long)best]; lblHigh.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
        lblHigh.fontSize = 18; lblHigh.position = CGPointMake(0, -20); [bg addChild:lblHigh];
    }
    SKLabelNode *lblIcon = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    lblIcon.text = @"↻"; lblIcon.fontColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    lblIcon.fontSize = 72; lblIcon.position = CGPointMake(-overlayW/2 + 50, -25); [bg addChild:lblIcon];
    
    SKLabelNode *lblTap = [SKLabelNode labelNodeWithFontNamed:@"Courier"];
    lblTap.text = @"Tap anywhere to restart"; lblTap.fontColor = [UIColor grayColor];
    lblTap.fontSize = 12; lblTap.position = CGPointMake(0, -overlayH/2 + 15); [bg addChild:lblTap];
}

- (void)render {
    [self.gameLayer removeAllChildren];
    NSUInteger cnt = self.snake.count;
    for (NSUInteger idx = 0; idx < cnt; idx++) {
        CGPoint p = self.snake[idx].CGPointValue;
        float fade = MAX(1.0f - idx * 0.04f, 0.45f);
        SKShapeNode *sNode;
        if (idx == 0) {
            sNode = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(kGridSize-2, kGridSize-2) cornerRadius:3];
            sNode.fillColor = [UIColor colorWithRed:0.4 green:1.0 blue:1.0 alpha:1.0];
        } else {
            sNode = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(kGridSize-2, kGridSize-2)];
            sNode.fillColor = [UIColor colorWithRed:0.15f*fade green:0.75f*fade blue:1.0 alpha:0.75f + 0.25f*fade];
        }
        sNode.lineWidth = 0;
        sNode.position = CGPointMake(p.x * kGridSize, p.y * kGridSize);
        [self.gameLayer addChild:sNode];
    }
}
@end