#import "ADSGames.h"
#import <AVFoundation/AVFoundation.h>

@implementation ADSGameMenuScene {
    SKLabelNode *_closeBtn;
    SKShapeNode *_btnPyEater;
    SKShapeNode *_btnJailTris;
    SKLabelNode *_dedicationBtn;
    AVAudioEngine *_audioEngine;
    AVAudioSourceNode *_sourceNode;
    ADSSynthState *_synthState;
}

- (void)willMoveFromView:(SKView *)view {
    if (_audioEngine) { [_audioEngine stop]; _audioEngine = nil; }
    _sourceNode = nil;
    if (_synthState) { free(_synthState); _synthState = NULL; }
}

- (void)didMoveToView:(SKView *)view {
    self.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    
    _synthState = malloc(sizeof(ADSSynthState));
    memset(_synthState, 0, sizeof(ADSSynthState));
    _audioEngine = [[AVAudioEngine alloc] init];
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:1];
    ADSSynthState *state = _synthState;
    
    _sourceNode = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *ts, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
        float *outBuf = (float *)outputData->mBuffers[0].mData;
        for (AVAudioFrameCount i = 0; i < frameCount; i++) {
            float sfxSamp = 0;
            if (state->sfxDur > 0) {
                state->sfxPhase += (state->sfxFreq * 2.0 * M_PI) / 44100.0;
                if (state->sfxPhase > 2.0 * M_PI) state->sfxPhase -= 2.0 * M_PI;
                sfxSamp = (state->sfxPhase < M_PI ? 0.2 : -0.2); 
                state->sfxDur -= 1.0/44100.0;
            }
            outBuf[i] = sfxSamp;
        }
        return noErr;
    }];
    
    [_audioEngine attachNode:_sourceNode];
    [_audioEngine connect:_sourceNode to:_audioEngine.mainMixerNode format:format];
    [_audioEngine startAndReturnError:nil];
    
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

    _btnPyEater = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(200, 80) cornerRadius:12];
    _btnPyEater.position = CGPointMake(self.size.width/2, self.size.height/2 - 28);
    _btnPyEater.fillColor = [UIColor clearColor];
    _btnPyEater.strokeColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    _btnPyEater.lineWidth = 3.0;
    [self addChild:_btnPyEater];
    
    SKLabelNode *pyEaterLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    pyEaterLbl.text = @"🐍 PYEATER";
    pyEaterLbl.fontColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    pyEaterLbl.fontSize = 18;
    pyEaterLbl.position = CGPointMake(0, -6);
    [_btnPyEater addChild:pyEaterLbl];

    _btnJailTris = [SKShapeNode shapeNodeWithRectOfSize:CGSizeMake(200, 80) cornerRadius:12];
    _btnJailTris.position = CGPointMake(self.size.width/2, self.size.height/2 + 72);
    _btnJailTris.fillColor = [UIColor clearColor];
    _btnJailTris.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    _btnJailTris.lineWidth = 3.0;
    [self addChild:_btnJailTris];
    
    SKLabelNode *jailTrisLbl = [SKLabelNode labelNodeWithFontNamed:@"Courier-Bold"];
    jailTrisLbl.text = @"🧱 JAILTRIS";
    jailTrisLbl.fontColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    jailTrisLbl.fontSize = 18;
    jailTrisLbl.position = CGPointMake(0, -6);
    [_btnJailTris addChild:jailTrisLbl];

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

- (void)playSFX:(float)freq dur:(float)dur {
    if (_synthState) { _synthState->sfxFreq = freq; _synthState->sfxDur = dur; }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint loc = [[touches anyObject] locationInNode:self];
    void (^playTap)(void) = ^{
        UIImpactFeedbackGenerator *feed = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feed impactOccurred];
    };
    if ([_closeBtn containsPoint:loc]) {
        playTap();
        if (self.exitHandler) self.exitHandler();
        return;
    }
    if ([_dedicationBtn containsPoint:loc]) {
        playTap();
        NSURL *url = [NSURL URLWithString:@"https://github.com/00000000aaaaaaaa"];
        if ([[UIApplication sharedApplication] canOpenURL:url]) { [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil]; }
        return;
    }
    if ([_btnPyEater containsPoint:loc]) {
        playTap();
        [self playSFX:440.0 dur:0.1];
        if (self.onSelectGame) self.onSelectGame(0);
    } else if ([_btnJailTris containsPoint:loc]) {
        playTap();
        [self playSFX:660.0 dur:0.1];
        if (self.onSelectGame) self.onSelectGame(1);
    }
}
@end

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
    if (motion == UIEventSubtypeMotionShake) { if (!self.gameView) [self launchGame]; }
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
    UITableView *table = nil;
    @try { table = (UITableView *)[self valueForKey:@"_table"]; }
    @catch (NSException *) {}
    if (![table isKindOfClass:[UITableView class]]) return;
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

    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.5 animations:^{
        weakSelf.gameView.alpha = 1.0;
    } completion:^(BOOL finished) {
        CGRect footerRect = [table convertRect:table.tableFooterView.bounds fromView:table.tableFooterView];
        [table scrollRectToVisible:footerRect animated:YES];
        table.scrollEnabled = NO;
    }];
}

- (void)teardownGame {
    if (!self.gameView) return;
    UITableView *table = nil;
    @try { table = (UITableView *)[self valueForKey:@"_table"]; }
    @catch (NSException *) {}
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