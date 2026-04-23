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
    if (_audioEngine) { [_audioEngine stop]; _audioEngine = nil; }
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
    CGFloat boardWidth = kRopCols * kRopGrid; CGFloat boardHeight = kRopRows * kRopGrid;
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
        float korobeiniki[] = { 659.25, 493.88, 523.25, 587.33, 523.25, 493.88, 440.0, 440.0, 523.25, 659.25, 587.33, 523.25, 493.88, 493.88, 523.25, 587.33, 659.25, 523.25, 440.0, 440.0, 0, 0, 0, 0 };
        for (AVAudioFrameCount i = 0; i < frameCount; i++) {
            float bgmSamp = 0;
            if (state->playBGM) {
                state->bgmTime += 1.0/44100.0;
                if (state->bgmTime > 0.25) { state->bgmTime = 0; state->bgmIdx = (state->bgmIdx + 1) % 24; }
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
                sfxSamp = (state->sfxPhase < M_PI ? 0.2 : -0.2); state->sfxDur -= 1.0/44100.0;
            }
            outBuf[i] = bgmSamp + sfxSamp;
        }
        return noErr;
    }];
    [_audioEngine attachNode:_sourceNode]; [_audioEngine connect:_sourceNode to:_audioEngine.mainMixerNode format:format]; [_audioEngine startAndReturnError:nil];
}

- (void)playSFX:(float)freq dur:(float)dur { if (_synthState) { _synthState->sfxFreq = freq; _synthState->sfxDur = dur; } }

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
    CGFloat boardWidth = kRopCols * kRopGrid; CGFloat boardHeight = kRopRows * kRopGrid;
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
    [self runAction:[SKAction runBlock:^{ [self playSFX:1046.50 dur:0.4]; }]];
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
                [self playSFX:150.0 dur:0.05];
                UIImpactFeedbackGenerator *heavyFeed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy]; [heavyFeed impactOccurred];
                [self render];
                
                UIColor *c = [self colorForType:_bType];
                NSMutableDictionary *colMinY = [NSMutableDictionary dictionary]; NSMutableDictionary *colMaxY = [NSMutableDictionary dictionary];
                for (int i = 0; i < 4; i++) {
                    int nx = _bX + rop_blocks[_bType][_bRot][i][0];
                    int nyBot = _bY + rop_blocks[_bType][_bRot][i][1];
                    int nyTop = startY + rop_blocks[_bType][_bRot][i][1];
                    if (!colMinY[@(nx)] || nyBot < [colMinY[@(nx)] intValue]) colMinY[@(nx)] = @(nyBot);
                    if (!colMaxY[@(nx)] || nyTop > [colMaxY[@(nx)] intValue]) colMaxY[@(nx)] = @(nyTop);
                }
                for (NSNumber *nxNum in colMinY) {
                    int nx = nxNum.intValue; int nyBot = [colMinY[nxNum] intValue]; int nyTop = [colMaxY[nxNum] intValue];
                    CGFloat height = (nyTop - nyBot + 1) * kRopGrid;
                    SKShapeNode *trail = [SKShapeNode shapeNodeWithRect:CGRectMake(0, 0, kRopGrid, height)];
                    trail.position = CGPointMake(self->_gameLayer.position.x + nx * kRopGrid, self->_gameLayer.position.y + nyBot * kRopGrid);
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
                for (int i = 1; i <= blocksToMove; i++) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.025 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if ([self isValidX:self->_bX + dir y:self->_bY rot:self->_bRot type:self->_bType]) {
                            self->_bX += dir; UIImpactFeedbackGenerator *tickFeed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                            [tickFeed impactOccurred]; [self render];
                        }
                    });
                }
            } else {
                if ([self isValidX:self->_bX + dir y:self->_bY rot:self->_bRot type:self->_bType]) {
                    self->_bX += dir; UIImpactFeedbackGenerator *tickFeed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                    [tickFeed impactOccurred]; [self render];
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
    if (rotated) { UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium]; [feed impactOccurred]; [self render]; }
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
    _bRot = 0; _bX = (kRopCols / 2) - 1; _bY = kRopRows - 2;
    if (![self isValidX:_bX y:_bY rot:_bRot type:_bType]) [self die];
}

- (BOOL)isValidX:(int)x y:(int)y rot:(int)rot type:(int)type {
    for (int i=0; i<4; i++) {
        int nx = x + rop_blocks[type][rot][i][0]; int ny = y + rop_blocks[type][rot][i][1];
        if (nx < 0 || nx >= kRopCols || ny < 0 || ny >= kRopRows) return NO;
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
        int nx = _bX + rop_blocks[_bType][_bRot][i][0]; int ny = _bY + rop_blocks[_bType][_bRot][i][1];
        _board[[NSString stringWithFormat:@"%d,%d", nx, ny]] = c;
    }
    UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [feed impactOccurred];
    if (!_justSlammed) [self playSFX:150.0 dur:0.05];
}

- (void)clearLines {
    NSMutableArray *linesToClear = [NSMutableArray array];
    for (int y = 0; y < kRopRows; y++) {
        BOOL full = YES;
        for (int x = 0; x < kRopCols; x++) { if (!_board[[NSString stringWithFormat:@"%d,%d", x, y]]) { full = NO; break; } }
        if (full) [linesToClear addObject:@(y)];
    }
    int linesCleared = (int)linesToClear.count; if (linesCleared == 0) return;
    _isPaused = YES; 
    for (NSNumber *yNum in linesToClear) {
        int y = yNum.intValue;
        for (int x = 0; x < kRopCols; x++) { [_board removeObjectForKey:[NSString stringWithFormat:@"%d,%d", x, y]]; }
    }
    int scoreAdd = (linesCleared == 4) ? 8 : linesCleared; _score += scoreAdd; _totalLinesCleared += linesCleared;
    _scoreLbl.text = [NSString stringWithFormat:@"CURRENT SCORE: %ld", (long)_score]; _tickRate = MAX(0.1, 0.5 - (_totalLinesCleared * 0.02)); 
    
    if (!_hasSurpassedHighScore && _score > _savedHighScore && _savedHighScore > 0) {
        _hasSurpassedHighScore = YES;
        [self runAction:[SKAction sequence:@[ [SKAction runBlock:^{ [self playSFX:987.77 dur:0.1]; }], [SKAction waitForDuration:0.1], [SKAction runBlock:^{ [self playSFX:1318.51 dur:0.2]; }] ]]];
    }
    
    SKAction *waitDrop = [SKAction waitForDuration:0.4];
    [self runAction:[SKAction sequence:@[waitDrop, [SKAction runBlock:^{
        int dropCount = 0;
        for (int y = 0; y < kRopRows; y++) {
            if ([linesToClear containsObject:@(y)]) { dropCount++; } else if (dropCount > 0) {
                for (int x = 0; x < kRopCols; x++) {
                    UIColor *above = self->_board[[NSString stringWithFormat:@"%d,%d", x, y]];
                    if (above) {
                        self->_board[[NSString stringWithFormat:@"%d,%d", x, y - dropCount]] = above;
                        [self->_board removeObjectForKey:[NSString stringWithFormat:@"%d,%d", x, y]];
                    }
                }
            }
        }
        self->_isPaused = NO; [self render]; if (!self->_isDead) [self spawnBlock];
    }]]]];

    if (linesCleared == 4) {
        [self runAction:[SKAction sequence:@[ [SKAction runBlock:^{ [self playSFX:523.25 dur:0.1]; }], [SKAction waitForDuration:0.12], [SKAction runBlock:^{ [self playSFX:659.25 dur:0.1]; }], [SKAction waitForDuration:0.12], [SKAction runBlock:^{ [self playSFX:783.99 dur:0.1]; }], [SKAction waitForDuration:0.12], [SKAction runBlock:^{ [self playSFX:1046.50 dur:0.3]; }] ]]];
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
        
        [msgContainer runAction:[SKAction sequence:@[[SKAction waitForDuration:1.5], [SKAction group:@[[SKAction moveByX:0 y:50 duration:0.6], [SKAction fadeOutWithDuration:0.6]]], [SKAction removeFromParent]]]];
        UINotificationFeedbackGenerator *successFeed = [[UINotificationFeedbackGenerator alloc] init]; [successFeed notificationOccurred:UINotificationFeedbackTypeSuccess];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [successFeed notificationOccurred:UINotificationFeedbackTypeWarning]; });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [successFeed notificationOccurred:UINotificationFeedbackTypeSuccess]; });
    } else {
        NSMutableArray *beeps = [NSMutableArray array];
        for (int i = 0; i < linesCleared; i++) { [beeps addObject:[SKAction runBlock:^{ [self playSFX:880.0 dur:0.05]; }]]; if (i < linesCleared - 1) [beeps addObject:[SKAction waitForDuration:0.08]]; }
        [self runAction:[SKAction sequence:beeps]];
        SKAction *s1 = [SKAction moveByX:-6 y:3 duration:0.04]; SKAction *s2 = [SKAction moveByX:12 y:-6 duration:0.04]; SKAction *s3 = [SKAction moveByX:-12 y:6 duration:0.04]; SKAction *sCenter = [SKAction moveByX:6 y:-3 duration:0.04];
        [self->_gameLayer runAction:[SKAction sequence:@[s1, s2, s3, sCenter]]];
        SKAction *colorHighlight = [SKAction runBlock:^{ self->_scoreLbl.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; }];
        [self->_scoreLbl runAction:[SKAction sequence:@[colorHighlight, [SKAction scaleTo:1.5 duration:0.15], [SKAction scaleTo:1.0 duration:0.15], [SKAction runBlock:^{ self->_scoreLbl.fontColor = [UIColor whiteColor]; }]]]];
    }
}

- (void)render {
    [_gameLayer removeAllChildren]; [_previewNode removeAllChildren];
    SKShapeNode *border = [SKShapeNode shapeNodeWithRect:CGRectMake(-2, -2, (kRopCols * kRopGrid) + 3, (kRopRows * kRopGrid) + 4)];
    border.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; border.lineWidth = 2.0; [_gameLayer addChild:border];
    
    for (NSString *key in _board) {
        NSArray *comps = [key componentsSeparatedByString:@","]; int x = [comps[0] intValue], y = [comps[1] intValue];
        SKShapeNode *node = [SKShapeNode shapeNodeWithRect:CGRectMake(x*kRopGrid, y*kRopGrid, kRopGrid-1, kRopGrid-1)];
        node.fillColor = _board[key]; node.lineWidth = 0; [_gameLayer addChild:node];
    }
    
    if (_isPlaying && !_isDead && !_isPaused) {
        int ghostY = _bY; while ([self isValidX:_bX y:ghostY-1 rot:_bRot type:_bType]) ghostY--;
        int shadowHeight = _bY - ghostY;
        if (shadowHeight > 0) {
            UIColor *shadowCol = [UIColor colorWithWhite:0.08 alpha:1.0];
            NSMutableDictionary *colMins = [NSMutableDictionary dictionary];
            for (int i=0; i<4; i++) {
                int nx = _bX + rop_blocks[_bType][_bRot][i][0]; int ny = _bY + rop_blocks[_bType][_bRot][i][1];
                if (!colMins[@(nx)] || ny < [colMins[@(nx)] intValue]) { colMins[@(nx)] = @(ny); }
            }
            for (NSNumber *nxNum in colMins) {
                int nx = nxNum.intValue; int pBotY = [colMins[nxNum] intValue]; int gTopY = pBotY - shadowHeight;
                if (pBotY > gTopY + 1) {
                    SKShapeNode *shNode = [SKShapeNode shapeNodeWithRect:CGRectMake(nx*kRopGrid, (gTopY+1)*kRopGrid, kRopGrid, (pBotY - gTopY - 1)*kRopGrid)];
                    shNode.fillColor = shadowCol; shNode.lineWidth = 0; [_gameLayer addChild:shNode];
                }
            }
        }
        UIColor *gC = [UIColor colorWithWhite:0.15 alpha:1.0];
        for (int i=0; i<4; i++) {
            int nx = _bX + rop_blocks[_bType][_bRot][i][0]; int ny = ghostY + rop_blocks[_bType][_bRot][i][1];
            SKShapeNode *node = [SKShapeNode shapeNodeWithRect:CGRectMake(nx*kRopGrid, ny*kRopGrid, kRopGrid-1, kRopGrid-1)];
            node.fillColor = gC; node.lineWidth = 0; [_gameLayer addChild:node];
        }
        UIColor *c = [self colorForType:_bType];
        for (int i=0; i<4; i++) {
            int nx = _bX + rop_blocks[_bType][_bRot][i][0]; int ny = _bY + rop_blocks[_bType][_bRot][i][1];
            SKShapeNode *node = [SKShapeNode shapeNodeWithRect:CGRectMake(nx*kRopGrid, ny*kRopGrid, kRopGrid-1, kRopGrid-1)];
            node.fillColor = c; node.lineWidth = 0; [_gameLayer addChild:node];
        }
        UIColor *nc = [self colorForType:_nextType]; CGFloat pGrid = 14.0; 
        for (int i=0; i<4; i++) {
            int nx = rop_blocks[_nextType][0][i][0]; int ny = rop_blocks[_nextType][0][i][1];
            SKShapeNode *nNode = [SKShapeNode shapeNodeWithRect:CGRectMake(nx*pGrid, ny*pGrid, pGrid-1, pGrid-1)];
            nNode.fillColor = nc; nNode.lineWidth = 0; [_previewNode addChild:nNode];
        }
    }
}

- (void)die {
    _isDead = YES; _isPlaying = NO; _highScoreBg.hidden = NO; _highScoreBg.position = CGPointMake(self.size.width / 2, 106);
    if (_synthState) _synthState->playBGM = 0;
    
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    NSInteger best = [def integerForKey:@"ADS_JailTrisHighScore"]; BOOL isNewHigh = NO;
    if (_score > best) { best = _score; [def setInteger:best forKey:@"ADS_JailTrisHighScore"]; [def synchronize]; isNewHigh = YES; }

    if (isNewHigh && _score > 0) {
        [self runAction:[SKAction sequence:@[ [SKAction runBlock:^{ [self playSFX:523.25 dur:0.1]; }], [SKAction waitForDuration:0.12], [SKAction runBlock:^{ [self playSFX:659.25 dur:0.1]; }], [SKAction waitForDuration:0.12], [SKAction runBlock:^{ [self playSFX:783.99 dur:0.1]; }], [SKAction waitForDuration:0.12], [SKAction runBlock:^{ [self playSFX:1046.50 dur:0.4]; }] ]]];
    } else { [self playSFX:150.0 dur:0.5]; }
    
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