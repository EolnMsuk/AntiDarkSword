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
}
static const CGFloat kGridSize = 20.0;

- (int)minX { return 2; }
- (int)maxX { return (self.size.width / kGridSize) - 2; }
- (int)minY { return 4; } 
- (int)maxY { return (self.size.height / kGridSize) - 3; } 

- (void)willMoveFromView:(SKView *)view {
    if (_audioEngine) { [_audioEngine stop]; _audioEngine = nil; }
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

- (void)playSFX:(float)freq dur:(float)dur { if (_synthState) { _synthState->sfxFreq = freq; _synthState->sfxDur = dur; } }

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
    self.musicBtnBg.position = CGPointMake(self.size.width - 36, 25);
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
    self.highScoreBtn.position = CGPointMake(90, 24);
    self.highScoreBtn.hidden = NO;
    
    SKShapeNode *hsBorder = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(140, 28) cornerRadius:14];
    hsBorder.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
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
    if ([_menuBg containsPoint:loc]) { playTap(); if (self.exitHandler) self.exitHandler(); return; }
    if ([self.musicBtnBg containsPoint:loc]) { playTap(); _musicEnabled = !_musicEnabled; [self updateMusicBtn]; return; }
    if ([self.highScoreBtn containsPoint:loc]) { playTap(); [self playSFX:1046.50 dur:0.4]; [self showLeaderboard]; return; }

    if (self.gameState == ADSGameStateMenu || self.gameState == ADSGameStateDead) {
        playTap(); [self resetGame];
    } else if (self.gameState == ADSGameStatePlaying) {
        if ([_pauseBg containsPoint:loc]) {
            playTap(); self.gameState = ADSGameStatePaused; self.startBtn.text = @"▶ RESUME";
            self.startBtn.hidden = NO; self.restartOverlay.hidden = NO;
            if (_synthState) _synthState->playBGM = 0;
        }
    } else if (self.gameState == ADSGameStatePaused) {
        if ([self.startBtn containsPoint:loc] || (!self.restartOverlay.hidden && [self.restartOverlay containsPoint:loc])) {
            playTap(); self.gameState = ADSGameStatePlaying; self.startBtn.hidden = YES; self.restartOverlay.hidden = YES;
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
    
    if (changed) { UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [feed impactOccurred]; }
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
    BOOL valid = NO; int x = 0, y = 0;
    while (!valid) {
        x = [self minX] + arc4random_uniform([self maxX] - [self minX] + 1);
        y = [self minY] + arc4random_uniform([self maxY] - [self minY] + 1);
        valid = YES;
        CGPoint testPoint = CGPointMake(x, y);
        for (NSValue *val in self.snake) { if (CGPointEqualToPoint(val.CGPointValue, testPoint)) { valid = NO; break; } }
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
    for (NSValue *val in self.snake) { if (CGPointEqualToPoint(val.CGPointValue, next)) { [self die]; return; } }
    
    [self.snake insertObject:[NSValue valueWithCGPoint:next] atIndex:0];
    
    if (CGPointEqualToPoint(next, self.food)) {
        self.score += 10; self.scoreLbl.text = [NSString stringWithFormat:@"SCORE: %ld", (long)self.score];
        if (!_hasSurpassedHighScore && self.score > _savedHighScore && _savedHighScore > 0) {
            _hasSurpassedHighScore = YES;
            [self runAction:[SKAction sequence:@[ [SKAction runBlock:^{ [self playSFX:987.77 dur:0.1]; }], [SKAction waitForDuration:0.1], [SKAction runBlock:^{ [self playSFX:1318.51 dur:0.2]; }] ]]];
        } else { [self playSFX:880.0 dur:0.1]; }
        UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
        [feed impactOccurred]; [self spawnFood];
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
        [self runAction:[SKAction sequence:@[ [SKAction runBlock:^{ [self playSFX:523.25 dur:0.1]; }], [SKAction waitForDuration:0.12], [SKAction runBlock:^{ [self playSFX:659.25 dur:0.1]; }], [SKAction waitForDuration:0.12], [SKAction runBlock:^{ [self playSFX:783.99 dur:0.1]; }], [SKAction waitForDuration:0.12], [SKAction runBlock:^{ [self playSFX:1046.50 dur:0.4]; }] ]]];
    } else { [self playSFX:150.0 dur:0.5]; }
    
    UINotificationFeedbackGenerator *feed = [[UINotificationFeedbackGenerator alloc] init];
    [feed notificationOccurred:UINotificationFeedbackTypeWarning];
    
    SKShapeNode *flash = [SKShapeNode shapeNodeWithRectOfSize:self.size];
    flash.position = CGPointMake(self.size.width/2, self.size.height/2);
    flash.fillColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.5];
    [self addChild:flash]; [flash runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.3], [SKAction removeFromParent]]]];
    
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
    SKShapeNode *fNode = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(kGridSize-2, kGridSize-2)];
    fNode.fillColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0]; fNode.position = CGPointMake(self.food.x * kGridSize, self.food.y * kGridSize);
    SKAction *pulseUp = [SKAction scaleTo:1.2 duration:0.3]; SKAction *pulseDown = [SKAction scaleTo:0.8 duration:0.3];
    [fNode runAction:[SKAction repeatActionForever:[SKAction sequence:@[pulseUp, pulseDown]]]];
    [self.gameLayer addChild:fNode];
    for (NSValue *val in self.snake) {
        CGPoint p = val.CGPointValue;
        SKShapeNode *sNode = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(kGridSize-2, kGridSize-2)];
        sNode.fillColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0]; sNode.position = CGPointMake(p.x * kGridSize, p.y * kGridSize);
        [self.gameLayer addChild:sNode];
    }
}
@end