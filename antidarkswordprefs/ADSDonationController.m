#import "ADSDonationController.h"

// LaunchServices SPI declarations are evidenced in WebKit's
// PAL/pal/spi/cocoa/LaunchServicesSPI.h and webpushd/LaunchServicesSPI.h.
// Guard every selector. Disallow URL overrides so HTTPS is handled by the
// system-selected web browser, rather than Venmo's associated-domain app.
@protocol ADSBrowserConfiguration <NSObject>
@property (nonatomic) BOOL allowURLOverrides;
@end
@protocol ADSBrowserWorkspace <NSObject>
+ (id)defaultWorkspace;
- (void)openURL:(NSURL *)url configuration:(id)configuration
    completionHandler:(void (^)(NSDictionary *result, NSError *error))completion;
@end

static BOOL ADSDonationCanPresent(UIViewController *controller) {
    if (!controller.isViewLoaded || !controller.view.window || controller.presentedViewController ||
        controller.isBeingDismissed || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
    if (controller.navigationController && controller.navigationController.topViewController != controller) return NO;
    if (@available(iOS 13.0, *)) {
        if (controller.view.window.windowScene.activationState != UISceneActivationStateForegroundActive) return NO;
    }
    return YES;
}

static void ADSBrowserFailure(UIViewController *controller, NSString *message) {
    if (!ADSDonationCanPresent(controller)) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Unable to Open Browser"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

static void ADSOpenVenmoInBrowser(UIViewController *controller) {
    id<ADSBrowserConfiguration> configuration = [NSClassFromString(@"_LSOpenConfiguration") new];
    Class<ADSBrowserWorkspace> workspaceClass = (Class<ADSBrowserWorkspace>)NSClassFromString(@"LSApplicationWorkspace");
    id<ADSBrowserWorkspace> workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)] ? [workspaceClass defaultWorkspace] : nil;
    if (![configuration respondsToSelector:@selector(setAllowURLOverrides:)] ||
        ![workspace respondsToSelector:@selector(openURL:configuration:completionHandler:)]) {
        ADSBrowserFailure(controller, @"This iOS version does not expose the required browser route. The destination is https://venmo.com/EolnMsuk/.");
        return;
    }
    configuration.allowURLOverrides = NO;
    __weak UIViewController *weakController = controller;
    [workspace openURL:[NSURL URLWithString:@"https://venmo.com/EolnMsuk/"] configuration:configuration
        completionHandler:^(__unused NSDictionary *result, NSError *error) {
            if (!error) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                ADSBrowserFailure(weakController, @"The default browser could not open https://venmo.com/EolnMsuk/.");
            });
        }];
}

static NSArray<NSDictionary<NSString *, NSString *> *> *ADSWallets(void) {
    static NSArray *wallets;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        wallets = @[
            @{@"coin": @"BTC", @"network": @"Bitcoin Network", @"address": @"31uHLpioo1TbxAmo9kM7rrKcLz3wvcoZaL"},
            @{@"coin": @"ETH", @"network": @"Ethereum Network", @"address": @"0x6060BEA4305BC4259bcF1db5eDbe756b7b74a895"},
            @{@"coin": @"USDT", @"network": @"Ethereum Network", @"address": @"0x17f0c9d7229E9A1Ad1cAccbfEe7979CF39F2301F"},
            @{@"coin": @"USDC", @"network": @"Ethereum Network", @"address": @"0xD69Dc2a18e64E071d096435dD6f9DdD52B10785c"},
            @{@"coin": @"RNDR / ERC-20", @"network": @"Ethereum Network", @"address": @"0x9cc3fCc3b41a31cDC07E33930F1d622c3ed690E9"},
            @{@"coin": @"LTC", @"network": @"Litecoin Network", @"address": @"MNWMWwueZBoQSd7Ms9meQ1cMfeY16BA7E1"},
            @{@"coin": @"SOL", @"network": @"Solana Network", @"address": @"H2ydj95396KRErC4nMtK5B2BAjobPTyUh7LpYBFSmFnP"},
            @{@"coin": @"BNB", @"network": @"BNB Smart Chain Network", @"address": @"0x314148b89744663ad9F1Fb8EA6862a62abf2fC93"}
        ];
    });
    return wallets;
}

@interface ADSWalletCell : UITableViewCell
@property (nonatomic, strong) UILabel *coin;
@property (nonatomic, strong) UILabel *network;
@property (nonatomic, strong) UILabel *address;
@end

@implementation ADSWalletCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        _coin = [UILabel new]; _network = [UILabel new]; _address = [UILabel new];
        _coin.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        _coin.textColor = UIColor.labelColor;
        _network.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _network.textColor = UIColor.secondaryLabelColor;
        _address.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _address.textColor = UIColor.labelColor;
        _address.lineBreakMode = NSLineBreakByCharWrapping;
        for (UILabel *label in @[_coin, _network, _address]) {
            label.numberOfLines = 0;
            label.adjustsFontForContentSizeCategory = YES;
        }
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_coin, _network, _address]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 5;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:margins.topAnchor constant:6],
            [stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-6]
        ]];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.accessibilityHint = @"Double tap to copy this address.";
    }
    return self;
}
@end

@interface ADSDonationController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *walletTable;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSUUID *> *walletCopyTokens;
@end

@implementation ADSDonationController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Crypto Wallets";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.walletCopyTokens = [NSMutableDictionary dictionary];
    self.walletTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.walletTable.delegate = self;
    self.walletTable.dataSource = self;
    self.walletTable.rowHeight = UITableViewAutomaticDimension;
    self.walletTable.estimatedRowHeight = 145;
    [self.walletTable registerClass:ADSWalletCell.class forCellReuseIdentifier:@"wallet"];
    self.walletTable.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.walletTable];
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    cancel.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    cancel.titleLabel.adjustsFontForContentSizeCategory = YES;
    [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:cancel];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.walletTable.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.walletTable.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.walletTable.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.walletTable.bottomAnchor constraintEqualToAnchor:cancel.topAnchor constant:-8],
        [cancel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [cancel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [cancel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
        [cancel.heightAnchor constraintGreaterThanOrEqualToConstant:44]
    ]];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return ADSWallets().count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    ADSWalletCell *cell = [tableView dequeueReusableCellWithIdentifier:@"wallet" forIndexPath:path];
    NSDictionary *wallet = ADSWallets()[path.row];
    BOOL copied = self.walletCopyTokens[@(path.row)] != nil;
    cell.coin.text = copied ? [wallet[@"coin"] stringByAppendingString:@" · Copied"] : wallet[@"coin"];
    cell.network.text = wallet[@"network"];
    cell.address.text = wallet[@"address"];
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@%@", wallet[@"coin"], wallet[@"network"], wallet[@"address"], copied ? @", Copied" : @""];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSDictionary *wallet = ADSWallets()[path.row];
    UIPasteboard.generalPasteboard.string = wallet[@"address"];
    NSNumber *key = @(path.row);
    NSUUID *token = NSUUID.UUID;
    self.walletCopyTokens[key] = token;
    [tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, [wallet[@"coin"] stringByAppendingString:@" address copied"]);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        typeof(self) controller = weakSelf;
        if (!controller || controller.walletCopyTokens[key] != token) return;
        [controller.walletCopyTokens removeObjectForKey:key];
        if (controller.view.window) [controller.walletTable reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
    });
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.walletCopyTokens removeAllObjects];
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

void ADSPresentDonationMenu(UIViewController *controller, UIView *anchor) {
    NSCAssert(NSThread.isMainThread, @"Donation UI must originate on main");
    if (!ADSDonationCanPresent(controller)) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"💸 Donate" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak UIViewController *weakController = controller;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Venmo" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakController dismissViewControllerAnimated:YES completion:^{ ADSOpenVenmoInBrowser(weakController); }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Crypto" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakController dismissViewControllerAnimated:YES completion:^{
            UIViewController *presenter = weakController;
            if (!ADSDonationCanPresent(presenter)) return;
            UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[ADSDonationController new]];
            navigation.modalPresentationStyle = UIModalPresentationFormSheet;
            navigation.preferredContentSize = CGSizeMake(500, 640);
            [presenter presentViewController:navigation animated:YES completion:nil];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = anchor ?: controller.view;
    sheet.popoverPresentationController.sourceRect = anchor ? anchor.bounds : CGRectMake(CGRectGetMidX(controller.view.bounds), CGRectGetMidY(controller.view.bounds), 1, 1);
    [controller presentViewController:sheet animated:YES completion:nil];
}
