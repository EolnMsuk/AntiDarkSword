#import "ADSGames.h"
#import <AVFoundation/AVFoundation.h>

@interface ADSJailTrisScene ()
@property (nonatomic, strong) SKLabelNode *musicBtn;
@property (nonatomic, strong) SKShapeNode *musicBtnBg;
@end

@implementation ADSJailTrisScene {
    NSMutableDictionary *_board; 
    int _bX, _bY, _bType, _bRot, _nextType;
    NSTimeInterval _lastTick, _tickRate;
    NSInteger _score;
    NSInteger _totalLinesCleared;
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
    SKShapeNode *_menuBg;
    SKShapeNode *_pauseBg;
    SKShapeNode *_startBg;
    SKShapeNode *_highScoreBg;
    SKLabelNode *_titleLbl;
    BOOL _isDead, _isPlaying, _isPaused, _panHandled, _justSlammed;
    CGPoint _touchStartLoc;
    AVAudioEngine *_audioEngine;
    AVAudioSourceNode *_sourceNode;
    ADSSynthState *_synthState;
    BOOL _musicEnabled;
    BOOL _hasSurpassedHighScore;
    NSInteger _savedHighScore;
}

static const CGFloat kJTGrid = 22.0;
static const int kJTCols = 10;
static const int kJTRows = 20;

static int jt_blocks[7][4][4][2] = {
    { {{-1,0}, {0,0}, {1,0}, {2,0}}, {{0,1}, {0,0}, {0,-1}, {0,-2}}, {{-1,0}, {0,0}, {1,0}, {2,0}}, {{0,1}, {0,0}, {0,-1}, {0,-2}} },
    { {{-1,1}, {-1,0}, {0,0}, {1,0}}, {{1,1}, {0,1}, {0,0}, {0,-1}}, {{1,-1}, {1,0}, {0,0}, {-1,0}}, {{-1,-1}, {0,-1}, {0,0}, {0,1}} },
    { {{1,1}, {-1,0}, {0,0}, {1,0}}, {{1,-1}, {0,1}, {0,0}, {0,-1}}, {{-1,-1}, {1,0}, {0,0}, {-1,0}}, {{-1,1}, {0,-1}, {0,0}, {0,1}} },
    { {{0,1}, {1,1}, {0,0}, {1,0}}, {{0,1}, {1,1}, {0,0}, {1,0}}, {{0,1}, {1,1}, {0,0}, {1,0}}, {{0,1}, {1,1}, {0,0}, {1,0}} },
    { {{0,1}, {1,1}, {-1,0}, {0,0}}, {{0,1}, {0,0}, {1,0}, {1,-1}}, {{0,1}, {1,1}, {-1,0}, {0,0}}, {{0,1}, {0,0}, {1,0}, {1,-1}} },
    { {{0,1}, {-1,0}, {0,0}, {1,0}}, {{0,1}, {0,0}, {1,0}, {0,-1}}, {{-1,0}, {0,0}, {1,0}, {0,-1}}, {{0,1}, {-1,0}, {0,0}, {0,-1}} },
    { {{-1,1}, {0,1}, {0,0}, {1,0}}, {{1,1}, {1,0}, {0,0}, {0,-1}}, {{-1,1}, {0,1}, {0,0}, {1,0}}, {{1,1}, {1,0}, {0,0}, {0,-1}} }
};

- (void)willMoveFromView:(SKView *)view {
    if (_audioEngine) { [_audioEngine stop]; _audioEngine = nil; }
    _sourceNode = nil;
    if (_synthState) { free(_synthState); _synthState = NULL; }
    NSArray *gestures = [view.gestureRecognizers copy];
    for (UIGestureRecognizer *g in gestures) { [view removeGestureRecognizer:g]; }
}

- (void)didMoveToView:(SKView *)view {
    self.backgroundColor = [UIColor blackColor];
    _board = [NSMutableDictionary dictionary]; _tickRate = 0.5;
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    _savedHighScore = [def integerForKey:@"ADS_JailTrisHighScore"];
    [self setupAudio];
    _gameLayer = [SKNode node];
    CGFloat boardWidth = kJTCols * kJTGrid; CGFloat boardHeight = kJTRows * kJTGrid;
    _gameLayer.position = CGPointMake((self.size.width - boardWidth)/2.0, (self.size.height - boardHeight)/2.0 + 5);
    [self addChild:_gameLayer];
    [self setupUI]; [self setupGestures:view]; [self render];
}

- (void)setupAudio {
    _synthState = malloc(sizeof(ADSSynthState)); memset(_synthState, 0, sizeof(ADSSynthState));
    _musicEnabled = NO; _synthState->playBGM = 0;
    _audioEngine = [[AVAudioEngine alloc] init];
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:1];
    ADSSynthState *state = _synthState;
    _sourceNode = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *ts, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
        float *outBuf = (float *)outputData->mBuffers[0].mData;
        float mel[]  = { 659.25f,493.88f,523.25f,587.33f,523.25f,493.88f,440.0f,440.0f,
                         523.25f,659.25f,587.33f,523.25f,493.88f,493.88f,523.25f,587.33f,
                         659.25f,523.25f,440.0f,440.0f,0,0,0,0 };
        float bass[] = { 329.63f,246.94f,261.63f,293.66f,261.63f,246.94f,220.0f,220.0f,
                         261.63f,329.63f,293.66f,261.63f,246.94f,246.94f,261.63f,293.66f,
                         329.63f,261.63f,220.0f,220.0f,0,0,0,0 };
        const float sr = 44100.0f, tp = 2.0f*(float)M_PI;
        for (AVAudioFrameCount i = 0; i < frameCount; i++) {
            float bgmSamp = 0, arpSamp = 0;
            if (state->playBGM) {
                state->bgmTime += 1.0f/sr;
                if (state->bgmTime > 0.25f) { state->bgmTime = 0; state->bgmIdx = (state->bgmIdx + 1) % 24; }
                float mF = mel[state->bgmIdx], bF = bass[state->bgmIdx];
                if (mF > 0) {
                    state->bgmPhase += (mF * tp) / sr;
                    if (state->bgmPhase > tp) state->bgmPhase -= tp;
                    float t = state->bgmPhase / tp;
                    bgmSamp = (t < 0.5f ? 4.0f*t - 1.0f : 3.0f - 4.0f*t) * 0.028f;
                    state->bgmPhase2 += (bF * tp) / sr;
                    if (state->bgmPhase2 > tp) state->bgmPhase2 -= tp;
                    bgmSamp += (state->bgmPhase2 < (float)M_PI ? 0.012f : -0.012f);
                    state->bgmTime2 += 1.0f/sr;
                    if (state->bgmTime2 > 0.0625f) { state->bgmTime2 = 0; state->bgmIdx2 = (state->bgmIdx2 + 1) & 3; }
                    static const float arpM[] = {1.0f, 1.498f, 2.0f, 1.498f};
                    float aF = mF * arpM[state->bgmIdx2];
                    state->bgmPhase3 += (aF * tp) / sr;
                    if (state->bgmPhase3 > tp) state->bgmPhase3 -= tp;
                    arpSamp = (state->bgmPhase3 < (float)(M_PI * 0.25f) ? 0.007f : -0.007f);
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
    [_audioEngine attachNode:_sourceNode]; [_audioEngine connect:_sourceNode to:_audioEngine.mainMixerNode format:format]; [_audioEngine startAndReturnError:nil];
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
    _scoreLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _scoreLbl.text = @"CURRENT SCORE: 0"; _scoreLbl.fontSize = 14; _scoreLbl.fontColor = [UIColor whiteColor];
    _scoreLbl.position = CGPointMake(self.size.width / 2, 5); _scoreLbl.hidden = YES; [self addChild:_scoreLbl];

    _pauseBg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(44, 44) cornerRadius:8];
    _pauseBg.strokeColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0]; _pauseBg.fillColor = [UIColor clearColor];
    _pauseBg.position = CGPointMake(self.size.width - 32, self.size.height - 23); [self addChild:_pauseBg];
    _pauseBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _pauseBtn.text = @"||"; _pauseBtn.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    _pauseBtn.fontSize = 22; _pauseBtn.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter; _pauseBtn.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [_pauseBg addChild:_pauseBtn];

    _menuBg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(44, 44) cornerRadius:8];
    _menuBg.strokeColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0]; _menuBg.fillColor = [UIColor clearColor];
    _menuBg.position = CGPointMake(31, self.size.height - 23); [self addChild:_menuBg];
    _menuBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _menuBtn.text = @"<"; _menuBtn.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    _menuBtn.fontSize = 24; _menuBtn.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter; _menuBtn.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [_menuBg addChild:_menuBtn];
    
    self.musicBtnBg = [SKShapeNode shapeNodeWithCircleOfRadius:16];
    self.musicBtnBg.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; self.musicBtnBg.fillColor = [UIColor clearColor];
    self.musicBtnBg.lineWidth = 2.0; self.musicBtnBg.position = CGPointMake(self.size.width - 30, 25); [self addChild:self.musicBtnBg];
    self.musicBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    self.musicBtn.text = @"♫"; self.musicBtn.fontSize = 18;
    self.musicBtn.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter; self.musicBtn.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [self.musicBtnBg addChild:self.musicBtn]; [self updateMusicBtn];
    
    _highScoreBg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(180, 40) cornerRadius:8];
    _highScoreBg.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; _highScoreBg.fillColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    _highScoreBg.position = CGPointMake(self.size.width / 2, 106); [self addChild:_highScoreBg];
    _highScoreBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _highScoreBtn.text = @"🏆 HIGH SCORES"; _highScoreBtn.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _highScoreBtn.fontSize = 14; _highScoreBtn.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter; [_highScoreBg addChild:_highScoreBtn];
    
    _previewNode = [SKNode node];
    CGFloat boardWidth = kJTCols * kJTGrid; CGFloat boardHeight = kJTRows * kJTGrid;
    _previewNode.position = CGPointMake(_gameLayer.position.x + boardWidth - 42, _gameLayer.position.y + boardHeight - 37);
    _previewNode.alpha = 0.5; [self addChild:_previewNode];

    CGFloat overlayW = self.size.width - 60; CGFloat overlayH = (self.size.height - 120) / 2.0;
    _restartOverlay = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(overlayW, overlayH) cornerRadius:15];
    _restartOverlay.position = CGPointMake(self.size.width / 2, self.size.height / 2);
    _restartOverlay.fillColor = [UIColor colorWithWhite:0.0 alpha:0.8]; _restartOverlay.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _restartOverlay.lineWidth = 4.0; _restartOverlay.zPosition = 50; _restartOverlay.hidden = YES; [self addChild:_restartOverlay];

    _startBg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(140, 50) cornerRadius:10];
    _startBg.strokeColor = [UIColor clearColor]; _startBg.fillColor = [UIColor clearColor];
    _startBg.position = CGPointMake(self.size.width / 2, self.size.height / 2 + 5); _startBg.zPosition = 51; [self addChild:_startBg];
    _startBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _startBtn.text = @"▶ Start"; _startBtn.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _startBtn.fontSize = 28; _startBtn.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter; [_startBg addChild:_startBtn];
    
    _titleLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _titleLbl.text = @"🧱 JAILTRIS"; _titleLbl.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _titleLbl.fontSize = 30; _titleLbl.position = CGPointMake(self.size.width / 2, self.size.height - 90); _titleLbl.zPosition = 51; [self addChild:_titleLbl];

    _restartBtn = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    _restartBtn.text = @"↺"; _restartBtn.fontColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    _restartBtn.fontSize = 44; _restartBtn.position = CGPointMake(30, 10); [self addChild:_restartBtn];
}

- (void)updateMusicBtn {
    UIColor *onColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0]; UIColor *offColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    if (_musicEnabled) {
        self.musicBtn.fontColor = onColor; self.musicBtnBg.strokeColor = onColor;
        if (_synthState && _isPlaying && !_isPaused && !_isDead) _synthState->playBGM = 1;
    } else {
        self.musicBtn.fontColor = offColor; self.musicBtnBg.strokeColor = offColor;
        if (_synthState) _synthState->playBGM = 0;
    }
}

- (void)setupGestures:(SKView *)view {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.cancelsTouchesInView = NO; [view addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    tap.cancelsTouchesInView = NO; [view addGestureRecognizer:tap];
}

- (void)showLeaderboard {
    if (_leaderboardNode) return;
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    NSInteger best = [def integerForKey:@"ADS_JailTrisHighScore"];
    
    _leaderboardNode = [SKNode node]; _leaderboardNode.zPosition = 100; _leaderboardNode.alpha = 0;
    SKShapeNode *blocker = [SKShapeNode shapeNodeWithRectOfSize:self.size];
    blocker.position = CGPointMake(self.size.width/2, self.size.height/2);
    blocker.fillColor = [UIColor clearColor]; blocker.strokeColor = [UIColor clearColor]; [_leaderboardNode addChild:blocker];
    
    SKShapeNode *bg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(220, 140) cornerRadius:12];
    bg.fillColor = [UIColor colorWithWhite:0.1 alpha:0.95]; bg.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    bg.lineWidth = 2.0; bg.position = CGPointMake(self.size.width/2, self.size.height/2); [_leaderboardNode addChild:bg];
    
    SKLabelNode *title = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    title.text = @"HIGH SCORE"; title.fontColor = [UIColor whiteColor]; title.fontSize = 22; title.position = CGPointMake(0, 25); [bg addChild:title];
    SKLabelNode *val = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    val.text = [NSString stringWithFormat:@"%ld", (long)best]; val.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; val.fontSize = 36; val.position = CGPointMake(0, -15); [bg addChild:val];
    SKLabelNode *tap = [SKLabelNode labelNodeWithFontNamed:@"Courier"];
    tap.text = @"Tap anywhere to close"; tap.fontColor = [UIColor grayColor]; tap.fontSize = 12; tap.position = CGPointMake(0, -50); [bg addChild:tap];
    
    [self addChild:_leaderboardNode]; [_leaderboardNode runAction:[SKAction fadeInWithDuration:0.2]];
    [self runAction:[SKAction runBlock:^{ [self playSFX2:1046.50 freq2:1318.51 dur:0.4]; }]];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { _touchStartLoc = [[touches anyObject] locationInNode:self]; }

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint loc = [[touches anyObject] locationInNode:self];
    if (hypot(loc.x - _touchStartLoc.x, loc.y - _touchStartLoc.y) > 15) return;
    
    void (^playTap)(void) = ^{
        UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [feed impactOccurred];
    };

    if (_leaderboardNode) {
        playTap(); SKNode *node = _leaderboardNode; _leaderboardNode = nil;
        [node runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.2], [SKAction removeFromParent]]]]; return;
    }
    if ([_menuBg containsPoint:loc]) { playTap(); if (self.exitHandler) self.exitHandler(); return; }
    if ([self.musicBtnBg containsPoint:loc]) { playTap(); _musicEnabled = !_musicEnabled; [self updateMusicBtn]; return; }
    if (!_highScoreBg.hidden && [_highScoreBg containsPoint:loc]) { playTap(); [self showLeaderboard]; return; }
    if ([_restartBtn containsPoint:loc]) { playTap(); [self resetGame]; return; }
    if (_isDead) { playTap(); [self resetGame]; return; }

    if (!_isPlaying) {
        if ([_startBg containsPoint:loc] || (!_restartOverlay.hidden && [_restartOverlay containsPoint:loc])) { playTap(); [self resetGame]; }
    } else if (_isPlaying && !_isDead) {
        if ([_pauseBg containsPoint:loc] || (_isPaused && ([_startBg containsPoint:loc] || (!_restartOverlay.hidden && [_restartOverlay containsPoint:loc])))) {
            playTap(); _isPaused = !_isPaused;
            if (_isPaused) {
                _startBtn.text = @"▶ RESUME"; _startBg.hidden = NO; _restartOverlay.hidden = NO; _highScoreBg.hidden = NO; _highScoreBg.zPosition = 55;
                _startBg.position = CGPointMake(self.size.width / 2, self.size.height / 2 + 35);
                _highScoreBg.position = CGPointMake(self.size.width / 2, self.size.height / 2 - 25);
                if (_synthState) _synthState->playBGM = 0;
            } else {
                _startBg.hidden = YES; _restartOverlay.hidden = YES; _highScoreBg.hidden = YES; _highScoreBg.zPosition = 0;
                if (_synthState && _musicEnabled) _synthState->playBGM = 1;
            }
        }
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)sender {
    if (!_isPlaying || _isDead || _isPaused) return;
    if (sender.state == UIGestureRecognizerStateBegan || sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled) { _panHandled = NO; return; }
    if (sender.state == UIGestureRecognizerStateChanged && !_panHandled) {
        CGPoint translation = [sender translationInView:sender.view]; CGPoint velocity = [sender velocityInView:sender.view];
        if (translation.y > 20 && fabs(translation.y) > fabs(translation.x) * 1.5) {
            _panHandled = YES; _justSlammed = YES; int drops = 0;
            while ([self isValidX:_bX y:_bY - (drops + 1) rot:_bRot type:_bType]) drops++;
            if (drops > 0) {
                int startY = _bY; _bY -= drops;
                [self playSFXSweep:280.0 sweep:-1800.0 dur:0.08];
                UIImpactFeedbackGenerator *heavyFeed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy]; [heavyFeed impactOccurred];
                [self render];
                
                UIColor *c = [self colorForType:_bType];
                NSMutableDictionary *colMinY = [NSMutableDictionary dictionary]; NSMutableDictionary *colMaxY = [NSMutableDictionary dictionary];
                for (int i = 0; i < 4; i++) {
                    int nx = _bX + jt_blocks[_bType][_bRot][i][0];
                    int nyBot = _bY + jt_blocks[_bType][_bRot][i][1];
                    int nyTop = startY + jt_blocks[_bType][_bRot][i][1];
                    if (!colMinY[@(nx)] || nyBot < [colMinY[@(nx)] intValue]) colMinY[@(nx)] = @(nyBot);
                    if (!colMaxY[@(nx)] || nyTop > [colMaxY[@(nx)] intValue]) colMaxY[@(nx)] = @(nyTop);
                }
                for (NSNumber *nxNum in colMinY) {
                    int nx = nxNum.intValue; int nyBot = [colMinY[nxNum] intValue]; int nyTop = [colMaxY[nxNum] intValue];
                    CGFloat height = (nyTop - nyBot + 1) * kJTGrid;
                    SKShapeNode *trail = [SKShapeNode shapeNodeWithRect:CGRectMake(0, 0, kJTGrid, height)];
                    trail.position = CGPointMake(self->_gameLayer.position.x + nx * kJTGrid, self->_gameLayer.position.y + nyBot * kJTGrid);
                    trail.fillColor = [c colorWithAlphaComponent:0.4]; trail.lineWidth = 0; trail.zPosition = 5; [self addChild:trail];
                    [trail runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.30], [SKAction removeFromParent]]]];
                }
                
                SKAction *sLeft = [SKAction moveByX:-4 y:-2 duration:0.02]; SKAction *sRight = [SKAction moveByX:8 y:4 duration:0.02]; SKAction *sCenter = [SKAction moveByX:-4 y:-2 duration:0.02];
                [self->_gameLayer runAction:[SKAction sequence:@[sLeft, sRight, sCenter]]]; _lastTick = 0; 
            }
        } else if (fabs(translation.x) > 30) {
            int dir = translation.x > 0 ? 1 : -1; _panHandled = YES;
            int blocksToMove = (fabs(velocity.x) > 800 || fabs(translation.x) > 60) ? 3 : 1;
            if (blocksToMove > 1) {
                __weak typeof(self) ws = self;
                for (int i = 1; i <= blocksToMove; i++) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.025 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        __strong typeof(ws) ss = ws; if (!ss) return;
                        if (ss->_isPlaying && !ss->_isDead && !ss->_isPaused && [ss isValidX:ss->_bX + dir y:ss->_bY rot:ss->_bRot type:ss->_bType]) {
                            ss->_bX += dir;
                            UIImpactFeedbackGenerator *tickFeed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                            [tickFeed impactOccurred];
                            [ss playSFX2:220.0 freq2:440.0 dur:0.03];
                            [ss render];
                        }
                    });
                }
            } else {
                if ([self isValidX:self->_bX + dir y:self->_bY rot:self->_bRot type:self->_bType]) {
                    self->_bX += dir;
                    UIImpactFeedbackGenerator *tickFeed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                    [tickFeed impactOccurred];
                    [self playSFX2:220.0 freq2:440.0 dur:0.03];
                    [self render];
                }
            }
        }
    }
}

- (void)handleTap:(UITapGestureRecognizer *)sender {
    if (!_isPlaying || _isDead || _isPaused) return;
    CGPoint viewLoc = [sender locationInView:sender.view]; CGPoint loc = [self convertPointFromView:viewLoc];
    if ([_pauseBg containsPoint:loc] || [_menuBg containsPoint:loc] || [self.musicBtnBg containsPoint:loc] || [_restartBtn containsPoint:loc]) return;
    if (_bType == 3) return; 
    
    int nextRot = (_bRot + 1) % 4; BOOL rotated = NO;
    int xOffsets[] = {0, -1, 1, -2, 2};
    for (int i = 0; i < 5; i++) {
        if ([self isValidX:_bX + xOffsets[i] y:_bY rot:nextRot type:_bType]) { _bX += xOffsets[i]; _bRot = nextRot; rotated = YES; break; }
    }
    if (!rotated) {
        if ([self isValidX:_bX y:_bY+1 rot:nextRot type:_bType]) { _bY++; _bRot = nextRot; rotated = YES; }
        else if ([self isValidX:_bX y:_bY+2 rot:nextRot type:_bType]) { _bY += 2; _bRot = nextRot; rotated = YES; }
    }
    if (rotated) { UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium]; [feed impactOccurred]; [self playSFXSweep:380.0 sweep:1400.0 dur:0.05]; [self render]; }
}

- (void)resetGame {
    _isPlaying = YES; _isDead = NO; _isPaused = NO;
    _startBg.hidden = YES; _titleLbl.hidden = YES; _restartOverlay.hidden = YES; _highScoreBg.hidden = YES; _scoreLbl.hidden = NO;
    [_deathContainer removeFromParent]; _deathContainer = nil;
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    _savedHighScore = [def integerForKey:@"ADS_JailTrisHighScore"]; _hasSurpassedHighScore = NO;
    if (_synthState && _musicEnabled) _synthState->playBGM = 1;
    [_board removeAllObjects]; _score = 0; _totalLinesCleared = 0; _tickRate = 0.5; _scoreLbl.text = @"CURRENT SCORE: 0";
    _nextType = arc4random_uniform(7); [self spawnBlock];
}

- (void)spawnBlock {
    _justSlammed = NO; _bType = _nextType; _nextType = arc4random_uniform(7);
    _bRot = 0; _bX = (kJTCols / 2) - 1; _bY = kJTRows - 2;
    if (![self isValidX:_bX y:_bY rot:_bRot type:_bType]) [self die];
}

- (BOOL)isValidX:(int)x y:(int)y rot:(int)rot type:(int)type {
    for (int i=0; i<4; i++) {
        int nx = x + jt_blocks[type][rot][i][0]; int ny = y + jt_blocks[type][rot][i][1];
        if (nx < 0 || nx >= kJTCols || ny < 0 || ny >= kJTRows) return NO;
        if (_board[[NSString stringWithFormat:@"%d,%d", nx, ny]] != nil) return NO;
    }
    return YES;
}

- (void)update:(NSTimeInterval)currentTime {
    if (!_isPlaying || _isDead || _isPaused) return;
    if (currentTime - _lastTick < _tickRate) return;
    _lastTick = currentTime;
    if ([self isValidX:_bX y:_bY-1 rot:_bRot type:_bType]) { _bY--; } else { [self lockBlock]; [self clearLines]; if (!_isDead && !_isPaused) [self spawnBlock]; }
    [self render];
}

- (UIColor *)colorForType:(int)type {
    NSArray *colors = @[ [UIColor cyanColor], [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1.0], [UIColor orangeColor], [UIColor yellowColor], [UIColor greenColor], [UIColor colorWithRed:0.8 green:0.4 blue:1.0 alpha:1.0], [UIColor redColor] ];
    return colors[type];
}

- (void)lockBlock {
    UIColor *c = [self colorForType:_bType];
    for (int i=0; i<4; i++) {
        int nx = _bX + jt_blocks[_bType][_bRot][i][0]; int ny = _bY + jt_blocks[_bType][_bRot][i][1];
        _board[[NSString stringWithFormat:@"%d,%d", nx, ny]] = c;
    }
    UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [feed impactOccurred];
    if (!_justSlammed) [self playSFX2Sweep:220.0 freq2:440.0 sweep1:-700.0 sweep2:-700.0 dur:0.07];
}

- (void)clearLines {
    NSMutableArray *linesToClear = [NSMutableArray array];
    for (int y = 0; y < kJTRows; y++) {
        BOOL full = YES;
        for (int x = 0; x < kJTCols; x++) { if (!_board[[NSString stringWithFormat:@"%d,%d", x, y]]) { full = NO; break; } }
        if (full) [linesToClear addObject:@(y)];
    }
    int linesCleared = (int)linesToClear.count; if (linesCleared == 0) return;
    _isPaused = YES; 
    for (NSNumber *yNum in linesToClear) {
        int y = yNum.intValue;
        for (int x = 0; x < kJTCols; x++) { [_board removeObjectForKey:[NSString stringWithFormat:@"%d,%d", x, y]]; }
    }
    int scoreAdd = (linesCleared == 4) ? 8 : linesCleared; _score += scoreAdd; _totalLinesCleared += linesCleared;
    _scoreLbl.text = [NSString stringWithFormat:@"CURRENT SCORE: %ld", (long)_score]; _tickRate = MAX(0.1, 0.5 - (_totalLinesCleared * 0.02)); 
    
    if (!_hasSurpassedHighScore && _score > _savedHighScore && _savedHighScore > 0) {
        _hasSurpassedHighScore = YES;
        [self runAction:[SKAction sequence:@[ [SKAction runBlock:^{ [self playSFX2:987.77 freq2:1975.54 dur:0.1]; }], [SKAction waitForDuration:0.1], [SKAction runBlock:^{ [self playSFX2:1318.51 freq2:1975.54 dur:0.25]; }] ]]];
        SKLabelNode *bestLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
        bestLbl.text = @"🏆 NEW BEST!"; bestLbl.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
        bestLbl.fontSize = 18; bestLbl.position = CGPointMake(self.size.width/2, self.size.height - 65);
        bestLbl.zPosition = 200; bestLbl.alpha = 0; [self addChild:bestLbl];
        [bestLbl runAction:[SKAction sequence:@[
            [SKAction group:@[[SKAction fadeInWithDuration:0.12], [SKAction moveByX:0 y:8 duration:0.12]]],
            [SKAction waitForDuration:0.7],
            [SKAction group:@[[SKAction fadeOutWithDuration:0.3], [SKAction moveByX:0 y:22 duration:0.3]]],
            [SKAction removeFromParent]
        ]]];
    }
    
    SKAction *waitDrop = [SKAction waitForDuration:(linesCleared == 4 ? 1.4 : 0.4)];
    [self runAction:[SKAction sequence:@[waitDrop, [SKAction runBlock:^{
        int dropCount = 0;
        for (int y = 0; y < kJTRows; y++) {
            if ([linesToClear containsObject:@(y)]) { dropCount++; } else if (dropCount > 0) {
                for (int x = 0; x < kJTCols; x++) {
                    UIColor *above = self->_board[[NSString stringWithFormat:@"%d,%d", x, y]];
                    if (above) {
                        self->_board[[NSString stringWithFormat:@"%d,%d", x, y - dropCount]] = above;
                        [self->_board removeObjectForKey:[NSString stringWithFormat:@"%d,%d", x, y]];
                    }
                }
            }
        }
        self->_isPaused = NO; [self render]; if (!self->_isDead && self->_isPlaying) [self spawnBlock];
    }]]]];

    if (linesCleared == 4) {
        [self runAction:[SKAction sequence:@[
            [SKAction runBlock:^{ [self playSFX2:523.25 freq2:1046.50 dur:0.1]; }], [SKAction waitForDuration:0.12],
            [SKAction runBlock:^{ [self playSFX2:659.25 freq2:1318.51 dur:0.1]; }], [SKAction waitForDuration:0.12],
            [SKAction runBlock:^{ [self playSFX2:783.99 freq2:1567.98 dur:0.1]; }], [SKAction waitForDuration:0.12],
            [SKAction runBlock:^{ [self playSFX2:1046.50 freq2:1567.98 dur:0.4]; }]
        ]]];
        SKAction *s1 = [SKAction moveByX:-15 y:15 duration:0.03]; SKAction *s2 = [SKAction moveByX:30 y:-30 duration:0.03]; SKAction *s3 = [SKAction moveByX:-30 y:30 duration:0.03]; SKAction *sCenter = [SKAction moveByX:15 y:-15 duration:0.03];
        [self->_gameLayer runAction:[SKAction sequence:@[s1, s2, s3, sCenter]]];

        SKNode *msgContainer = [SKNode node]; msgContainer.position = CGPointMake(self.size.width/2, self.size.height/2); msgContainer.zPosition = 100; msgContainer.xScale = 0.1; msgContainer.yScale = 0.1; [self addChild:msgContainer];
        [msgContainer runAction:[SKAction sequence:@[[SKAction scaleTo:1.2 duration:0.2], [SKAction scaleTo:1.0 duration:0.1]]]];

        UIColor *gold = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
        SKShapeNode *bg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(280, 100) cornerRadius:10]; bg.fillColor = [UIColor colorWithWhite:0.05 alpha:1.0]; bg.strokeColor = gold; bg.lineWidth = 3.0; [msgContainer addChild:bg];
        SKShapeNode *glow = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(280, 100) cornerRadius:10]; glow.fillColor = [UIColor clearColor]; glow.strokeColor = [gold colorWithAlphaComponent:0.8]; glow.lineWidth = 8.0; [msgContainer addChild:glow];
        [glow runAction:[SKAction repeatActionForever:[SKAction sequence:@[[SKAction scaleTo:1.1 duration:0.3], [SKAction fadeAlphaTo:0.2 duration:0.3], [SKAction scaleTo:1.0 duration:0.3], [SKAction fadeAlphaTo:0.8 duration:0.3]]]]];

        SKLabelNode *line1 = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"]; line1.text = @"JailTris! 4x Row Bonus"; line1.fontColor = gold; line1.fontSize = 20; line1.position = CGPointMake(0, 10); [msgContainer addChild:line1];
        SKLabelNode *line2 = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"]; line2.text = @"+8 POINTS"; line2.fontColor = gold; line2.fontSize = 30; line2.position = CGPointMake(0, -28); [msgContainer addChild:line2];

        SKShapeNode *flash = [SKShapeNode shapeNodeWithRectOfSize:self.size]; flash.position = CGPointMake(self.size.width/2, self.size.height/2); flash.fillColor = gold; flash.alpha = 0.0; flash.zPosition = 99; [self addChild:flash];
        SKAction *strobe = [SKAction sequence:@[[SKAction fadeAlphaTo:0.9 duration:0.05], [SKAction fadeAlphaTo:0.0 duration:0.05], [SKAction fadeAlphaTo:0.7 duration:0.05], [SKAction fadeAlphaTo:0.0 duration:0.05], [SKAction fadeAlphaTo:0.5 duration:0.1], [SKAction fadeOutWithDuration:0.4]]];
        [flash runAction:[SKAction sequence:@[strobe, [SKAction removeFromParent]]]];

        NSArray *burstColors = @[gold, [UIColor whiteColor], [UIColor colorWithRed:1.0 green:0.5 blue:0.0 alpha:1.0], [UIColor colorWithRed:0.4 green:1.0 blue:1.0 alpha:1.0]];
        for (int b = 0; b < 12; b++) {
            CGFloat angle = b * (float)M_PI / 6.0f;
            CGFloat radius = (b % 3 == 0) ? 9.0f : (b % 3 == 1) ? 6.0f : 4.0f;
            SKShapeNode *burst = [SKShapeNode shapeNodeWithCircleOfRadius:radius]; burst.position = CGPointMake(self.size.width/2, self.size.height/2);
            burst.fillColor = burstColors[b % 4]; burst.strokeColor = [UIColor clearColor]; burst.zPosition = 97; [self addChild:burst];
            CGFloat dist = 55.0f + (b % 3) * 28.0f;
            CGFloat burstDur = 0.5f + (b % 2) * 0.12f;
            [burst runAction:[SKAction sequence:@[[SKAction group:@[[SKAction moveByX:cosf(angle)*dist y:sinf(angle)*dist duration:burstDur], [SKAction scaleTo:0.15 duration:burstDur], [SKAction fadeOutWithDuration:burstDur]]], [SKAction removeFromParent]]]];
        }

        [msgContainer runAction:[SKAction sequence:@[[SKAction waitForDuration:1.5], [SKAction group:@[[SKAction moveByX:0 y:50 duration:0.6], [SKAction fadeOutWithDuration:0.6]]], [SKAction removeFromParent]]]];
        UINotificationFeedbackGenerator *successFeed = [[UINotificationFeedbackGenerator alloc] init]; [successFeed notificationOccurred:UINotificationFeedbackTypeSuccess];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [successFeed notificationOccurred:UINotificationFeedbackTypeWarning]; });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [successFeed notificationOccurred:UINotificationFeedbackTypeSuccess]; });
    } else {
        [self showLineClearFX:linesToClear count:linesCleared];
        CGFloat shk = linesCleared * 3.0f;
        SKAction *sh1 = [SKAction moveByX:-shk y:shk*0.5f duration:0.04]; SKAction *sh2 = [SKAction moveByX:shk*2 y:-shk duration:0.04];
        SKAction *sh3 = [SKAction moveByX:-shk*2 y:shk duration:0.04]; SKAction *shC = [SKAction moveByX:shk y:-shk*0.5f duration:0.04];
        [_gameLayer runAction:[SKAction sequence:@[sh1, sh2, sh3, shC]]];
        SKAction *cOn = [SKAction runBlock:^{ self->_scoreLbl.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; }];
        [_scoreLbl runAction:[SKAction sequence:@[cOn, [SKAction scaleTo:1.4 duration:0.12], [SKAction scaleTo:1.0 duration:0.12], [SKAction runBlock:^{ self->_scoreLbl.fontColor = [UIColor whiteColor]; }]]]];
    }
}

- (void)render {
    [_gameLayer removeAllChildren]; [_previewNode removeAllChildren];
    SKShapeNode *border = [SKShapeNode shapeNodeWithRect:CGRectMake(-2, -2, (kJTCols * kJTGrid) + 3, (kJTRows * kJTGrid) + 4)];
    border.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; border.lineWidth = 2.0; [_gameLayer addChild:border];
    
    for (NSString *key in _board) {
        NSArray *comps = [key componentsSeparatedByString:@","]; int x = [comps[0] intValue], y = [comps[1] intValue];
        SKShapeNode *node = [SKShapeNode shapeNodeWithRect:CGRectMake(x*kJTGrid, y*kJTGrid, kJTGrid-1, kJTGrid-1)];
        node.fillColor = _board[key]; node.lineWidth = 0; [_gameLayer addChild:node];
    }
    
    if (_isPlaying && !_isDead && !_isPaused) {
        int ghostY = _bY; while ([self isValidX:_bX y:ghostY-1 rot:_bRot type:_bType]) ghostY--;
        int shadowHeight = _bY - ghostY;
        if (shadowHeight > 0) {
            UIColor *shadowCol = [UIColor colorWithWhite:0.08 alpha:1.0];
            NSMutableDictionary *colMins = [NSMutableDictionary dictionary];
            for (int i=0; i<4; i++) {
                int nx = _bX + jt_blocks[_bType][_bRot][i][0]; int ny = _bY + jt_blocks[_bType][_bRot][i][1];
                if (!colMins[@(nx)] || ny < [colMins[@(nx)] intValue]) { colMins[@(nx)] = @(ny); }
            }
            for (NSNumber *nxNum in colMins) {
                int nx = nxNum.intValue; int pBotY = [colMins[nxNum] intValue]; int gTopY = pBotY - shadowHeight;
                if (pBotY > gTopY + 1) {
                    SKShapeNode *shNode = [SKShapeNode shapeNodeWithRect:CGRectMake(nx*kJTGrid, (gTopY+1)*kJTGrid, kJTGrid, (pBotY - gTopY - 1)*kJTGrid)];
                    shNode.fillColor = shadowCol; shNode.lineWidth = 0; [_gameLayer addChild:shNode];
                }
            }
        }
        UIColor *gC = [UIColor colorWithWhite:0.15 alpha:1.0];
        for (int i=0; i<4; i++) {
            int nx = _bX + jt_blocks[_bType][_bRot][i][0]; int ny = ghostY + jt_blocks[_bType][_bRot][i][1];
            SKShapeNode *node = [SKShapeNode shapeNodeWithRect:CGRectMake(nx*kJTGrid, ny*kJTGrid, kJTGrid-1, kJTGrid-1)];
            node.fillColor = gC; node.lineWidth = 0; [_gameLayer addChild:node];
        }
        UIColor *c = [self colorForType:_bType];
        for (int i=0; i<4; i++) {
            int nx = _bX + jt_blocks[_bType][_bRot][i][0]; int ny = _bY + jt_blocks[_bType][_bRot][i][1];
            SKShapeNode *node = [SKShapeNode shapeNodeWithRect:CGRectMake(nx*kJTGrid, ny*kJTGrid, kJTGrid-1, kJTGrid-1)];
            node.fillColor = c; node.lineWidth = 0; [_gameLayer addChild:node];
        }
        UIColor *nc = [self colorForType:_nextType]; CGFloat pGrid = 14.0; 
        for (int i=0; i<4; i++) {
            int nx = jt_blocks[_nextType][0][i][0]; int ny = jt_blocks[_nextType][0][i][1];
            SKShapeNode *nNode = [SKShapeNode shapeNodeWithRect:CGRectMake(nx*pGrid, ny*pGrid, pGrid-1, pGrid-1)];
            nNode.fillColor = nc; nNode.lineWidth = 0; [_previewNode addChild:nNode];
        }
    }
}

- (void)showLineClearFX:(NSArray *)lines count:(int)count {
    UIColor *fc = (count == 1) ? [UIColor colorWithRed:0.4 green:1.0 blue:0.4 alpha:0.85]
                : (count == 2) ? [UIColor colorWithRed:0.4 green:0.9 blue:1.0 alpha:0.85]
                :                [UIColor colorWithRed:1.0 green:0.85 blue:0.1 alpha:0.90];
    CGFloat boardW = kJTCols * kJTGrid;
    for (NSNumber *yNum in lines) {
        int y = yNum.intValue;
        SKShapeNode *bar = [SKShapeNode shapeNodeWithRect:CGRectMake(_gameLayer.position.x - 2, _gameLayer.position.y + y * kJTGrid, boardW + 4, kJTGrid)];
        bar.fillColor = fc; bar.lineWidth = 0; bar.zPosition = 30; [self addChild:bar];
        [bar runAction:[SKAction sequence:@[
            [SKAction group:@[[SKAction scaleXTo:1.06 duration:0.05], [SKAction fadeAlphaTo:1.0 duration:0.05]]],
            [SKAction group:@[[SKAction scaleXTo:1.0 duration:0.12], [SKAction fadeOutWithDuration:0.18]]],
            [SKAction removeFromParent]
        ]]];
    }
    if (count == 1) {
        [self runAction:[SKAction runBlock:^{ [self playSFX2:880.0 freq2:1760.0 dur:0.12]; }]];
    } else if (count == 2) {
        [self runAction:[SKAction sequence:@[
            [SKAction runBlock:^{ [self playSFX2:880.0 freq2:1108.73 dur:0.10]; }],
            [SKAction waitForDuration:0.10],
            [SKAction runBlock:^{ [self playSFX2:1108.73 freq2:1318.51 dur:0.14]; }]
        ]]];
    } else {
        [self runAction:[SKAction sequence:@[
            [SKAction runBlock:^{ [self playSFX2:880.0 freq2:1108.73 dur:0.08]; }],
            [SKAction waitForDuration:0.08],
            [SKAction runBlock:^{ [self playSFX2:1108.73 freq2:1318.51 dur:0.08]; }],
            [SKAction waitForDuration:0.08],
            [SKAction runBlock:^{ [self playSFX2:1318.51 freq2:1760.0 dur:0.18]; }]
        ]]];
        SKShapeNode *wave = [SKShapeNode shapeNodeWithCircleOfRadius:5];
        wave.position = CGPointMake(self.size.width/2, self.size.height/2);
        wave.strokeColor = fc; wave.fillColor = [UIColor clearColor]; wave.lineWidth = 3.0; wave.zPosition = 98; [self addChild:wave];
        [wave runAction:[SKAction sequence:@[[SKAction group:@[[SKAction scaleTo:9.0 duration:0.35], [SKAction fadeOutWithDuration:0.35]]], [SKAction removeFromParent]]]];
    }
    {
        NSString *ptsStr = (count == 1) ? @"+1" : (count == 2) ? @"+2" : @"+3";
        SKLabelNode *ptsPop = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
        ptsPop.text = ptsStr; ptsPop.fontColor = fc; ptsPop.fontSize = 17;
        ptsPop.position = CGPointMake(self.size.width/2 + 68, self.size.height/2 - 8);
        ptsPop.zPosition = 101; ptsPop.alpha = 0; [self addChild:ptsPop];
        [ptsPop runAction:[SKAction sequence:@[
            [SKAction group:@[[SKAction fadeInWithDuration:0.06], [SKAction moveByX:0 y:12 duration:0.06]]],
            [SKAction waitForDuration:0.22],
            [SKAction group:@[[SKAction fadeOutWithDuration:0.26], [SKAction moveByX:0 y:20 duration:0.26]]],
            [SKAction removeFromParent]
        ]]];
    }
    if (count >= 2) {
        NSString *txt = (count == 2) ? @"2x LINE!" : @"3x COMBO!";
        SKLabelNode *combo = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
        combo.text = txt; combo.fontColor = fc; combo.fontSize = (count == 2) ? 20.0 : 26.0;
        combo.position = CGPointMake(self.size.width/2, self.size.height/2 + 10);
        combo.zPosition = 100; combo.alpha = 0; [self addChild:combo];
        [combo runAction:[SKAction sequence:@[
            [SKAction group:@[[SKAction fadeInWithDuration:0.07], [SKAction moveByX:0 y:8 duration:0.07]]],
            [SKAction waitForDuration:0.22],
            [SKAction group:@[[SKAction fadeOutWithDuration:0.28], [SKAction moveByX:0 y:28 duration:0.28]]],
            [SKAction removeFromParent]
        ]]];
    }
}

- (void)die {
    _isDead = YES; _isPlaying = NO; _highScoreBg.hidden = NO; _highScoreBg.position = CGPointMake(self.size.width / 2, 106);
    if (_synthState) _synthState->playBGM = 0;
    
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    NSInteger best = [def integerForKey:@"ADS_JailTrisHighScore"]; BOOL isNewHigh = NO;
    if (_score > best) { best = _score; [def setInteger:best forKey:@"ADS_JailTrisHighScore"]; [def synchronize]; isNewHigh = YES; }

    if (isNewHigh && _score > 0) {
        [self runAction:[SKAction sequence:@[
            [SKAction runBlock:^{ [self playSFX2:523.25 freq2:1046.50 dur:0.1]; }], [SKAction waitForDuration:0.12],
            [SKAction runBlock:^{ [self playSFX2:659.25 freq2:1318.51 dur:0.1]; }], [SKAction waitForDuration:0.12],
            [SKAction runBlock:^{ [self playSFX2:783.99 freq2:1567.98 dur:0.1]; }], [SKAction waitForDuration:0.12],
            [SKAction runBlock:^{ [self playSFX2:1046.50 freq2:1567.98 dur:0.45]; }]
        ]]];
    } else { [self playSFX2Sweep:300.0 freq2:150.0 sweep1:-400.0 sweep2:-200.0 dur:0.6]; }
    
    UINotificationFeedbackGenerator *feed = [[UINotificationFeedbackGenerator alloc] init]; [feed notificationOccurred:UINotificationFeedbackTypeWarning];
    SKShapeNode *flash = [SKShapeNode shapeNodeWithRectOfSize:self.size]; flash.position = CGPointMake(self.size.width/2, self.size.height/2); flash.fillColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.5]; flash.zPosition = 99; [self addChild:flash]; [flash runAction:[SKAction sequence:@[[SKAction fadeOutWithDuration:0.3], [SKAction removeFromParent]]]];
    
    _deathContainer = [SKNode node]; _deathContainer.zPosition = 60; [self addChild:_deathContainer];
    CGFloat overlayW = self.size.width - 60; CGFloat overlayH = (self.size.height - 180) / 2.0;
    SKShapeNode *bg = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(overlayW, overlayH) cornerRadius:15];
    bg.position = CGPointMake(self.size.width / 2, self.size.height / 2); bg.fillColor = [UIColor colorWithWhite:0.0 alpha:0.9]; bg.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; bg.lineWidth = 4.0; [_deathContainer addChild:bg];
    
    if (isNewHigh) {
        SKLabelNode *lblTitle = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"]; lblTitle.text = @"NEW HIGH SCORE!"; lblTitle.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; lblTitle.fontSize = 20; lblTitle.position = CGPointMake(0, 15); [bg addChild:lblTitle];
        SKLabelNode *lblScore = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"]; lblScore.text = [NSString stringWithFormat:@"%ld", (long)_score]; lblScore.fontColor = [UIColor whiteColor]; lblScore.fontSize = 28; lblScore.position = CGPointMake(0, -15); [bg addChild:lblScore];
    } else {
        SKLabelNode *lblScore = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"]; lblScore.text = [NSString stringWithFormat:@"SCORE: %ld", (long)_score]; lblScore.fontColor = [UIColor whiteColor]; lblScore.fontSize = 24; lblScore.position = CGPointMake(0, 10); [bg addChild:lblScore];
        SKLabelNode *lblHigh = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"]; lblHigh.text = [NSString stringWithFormat:@"BEST: %ld", (long)best]; lblHigh.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; lblHigh.fontSize = 18; lblHigh.position = CGPointMake(0, -15); [bg addChild:lblHigh];
    }
    SKLabelNode *lblIcon = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"]; lblIcon.text = @"↻"; lblIcon.fontColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0]; lblIcon.fontSize = 60; lblIcon.position = CGPointMake(-overlayW/2 + 40, -20); [bg addChild:lblIcon];
    SKLabelNode *lblTap = [SKLabelNode labelNodeWithFontNamed:@"Courier"]; lblTap.text = @"Tap anywhere to restart"; lblTap.fontColor = [UIColor grayColor]; lblTap.fontSize = 12; lblTap.position = CGPointMake(0, -overlayH/2 + 10); [bg addChild:lblTap];
}
@end