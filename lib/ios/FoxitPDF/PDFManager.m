//
//  PDFManager.m
//  FoxitReader
//
//  Created by user on 4/10/18.
//  Copyright © 2018 Facebook. All rights reserved.
//

#import "PDFManager.h"
#import <React/RCTBridgeModule.h>
#import <React/RCTViewManager.h>

static FSErrorCode errorCode = FSErrUnknown;
static FSFileListViewController *fileListVC;
static NSString *initializeSN;
static NSString *initializeKey;

@interface PDFNavigationController : UINavigationController
@property (nonatomic, weak) UIExtensionsManager *extensionsManager;
@end

@interface RNTPDFManager () <RCTBridgeModule, UIExtensionsManagerDelegate, IDocEventListener>
@property (nonatomic, strong) FSPDFViewCtrl* pdfViewCtrl;
@property (nonatomic, strong) UIViewController *pdfViewController;
@property (nonatomic, strong) PDFNavigationController* rootViewController;
@property (nonatomic, strong) UIExtensionsManager* extensionsManager;
@end

@implementation RNTPDFManager {

    NSDictionary* _topToolbarConfig;
    NSDictionary* _bottomToolbarConfig;
    NSDictionary* _panelConfig;
    NSDictionary* _viewSettingsConfig;
    NSDictionary* _viewMoreConfig;
    NSArray *topToolbarVerticalConstraints;

}

+ (FSErrorCode)initialize:(NSString *)sn
                      key:(NSString *)key{
    if (![initializeSN isEqualToString:sn] || ![initializeKey isEqualToString:key]) {
        if (errorCode == FSErrSuccess) [FSLibrary destroy];
        errorCode = [FSLibrary initialize:sn key:key];
        if (errorCode != FSErrSuccess) {
            return errorCode;
        }else{
            initializeSN = sn;
            initializeKey = key;
        }
        if (!fileListVC) fileListVC = [[FSFileListViewController alloc] init];
    }
    return errorCode;
}

+ (BOOL)requiresMainQueueSetup{
    return YES;
}

- (instancetype)init{
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationDidChange) name:UIDeviceOrientationDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
}

RCT_EXPORT_MODULE(PDFManager)

@synthesize bridge = _bridge;

RCT_EXPORT_METHOD(initialize:(NSString *)sn key:(NSString *)key){
    if ([RNTPDFManager initialize:sn key:key] != FSErrSuccess ) {
        [self showError:@"Check your sn or key"];
    }
}

RCT_EXPORT_METHOD(openDocument:(NSString *)src
                  password:(NSString *)password
                  extensionConfig:(NSDictionary *)extensionConfig
                  enableTopToolbar:(BOOL)enableTopToolbar
                  enableBottomToolbar:(BOOL)enableBottomToolbar
                  topToolbarConfig:(NSDictionary *)topToolbarConfig
                  bottomToolbarConfig:(NSDictionary *)bottomToolbarConfig
                  panelConfig:(NSDictionary *)panelConfig
                  viewSettingsConfig:(NSDictionary *)viewSettingsConfig
                  viewMoreConfig:(NSDictionary *)viewMoreConfig) {
        [self openPDF:src
             password:password
      extensionConfig:extensionConfig
     enableTopToolbar:enableTopToolbar
  enableBottomToolbar:enableBottomToolbar
     topToolbarConfig:topToolbarConfig
  bottomToolbarConfig:bottomToolbarConfig
          panelConfig:panelConfig
   viewSettingsConfig:viewSettingsConfig
       viewMoreConfig:viewMoreConfig];
}

RCT_EXPORT_METHOD(openPDF:(NSString *)src
                  password:(NSString *)password
                  extensionConfig:(NSDictionary *)extensionConfig
                  enableTopToolbar:(BOOL)enableTopToolbar
                  enableBottomToolbar:(BOOL)enableBottomToolbar
                  topToolbarConfig:(NSDictionary *)topToolbarConfig
                  bottomToolbarConfig:(NSDictionary *)bottomToolbarConfig
                  panelConfig:(NSDictionary *)panelConfig
                  viewSettingsConfig:(NSDictionary *)viewSettingsConfig
                  viewMoreConfig:(NSDictionary *)viewMoreConfig) {

    dispatch_async(dispatch_get_main_queue(), ^{
        

        if (errorCode != FSErrSuccess) {
            [self showError:@"Check your sn or key"];
            return;
        }
        
        self.pdfViewCtrl = [[FSPDFViewCtrl alloc] initWithFrame:[UIScreen mainScreen].bounds];
        [self.pdfViewCtrl setRMSAppClientId:@"972b6681-fa03-4b6b-817b-c8c10d38bd20" redirectURI:@"com.foxitsoftware.com.mobilepdf-for-ios://authorize"];
        [self.pdfViewCtrl registerDocEventListener:self];
    
        self.pdfViewController = [[UIViewController alloc] init];
        self.pdfViewController.automaticallyAdjustsScrollViewInsets = NO;
        
        self.pdfViewController.view = self.pdfViewCtrl;
        self.rootViewController = [[PDFNavigationController alloc] initWithRootViewController:self.pdfViewController];
        self.rootViewController.navigationBarHidden = YES;
        
        if ( extensionConfig != NULL) {
            NSData* configData = [NSJSONSerialization dataWithJSONObject:extensionConfig
                                                                 options:NSJSONWritingPrettyPrinted
                                                                   error: nil];
            
            self.extensionsManager = [[UIExtensionsManager alloc] initWithPDFViewControl:self.pdfViewCtrl configuration:configData];
        } else {
            
            self.extensionsManager = [[UIExtensionsManager alloc] initWithPDFViewControl:self.pdfViewCtrl];
        }

        self.rootViewController.extensionsManager = self.extensionsManager;
    
        self.extensionsManager.delegate = self;
        

        [self.extensionsManager enableBottomToolbar:enableBottomToolbar];
        [self.extensionsManager enableTopToolbar:enableTopToolbar];
        
        [self setPanelConfig:panelConfig];
        [self setViewMoreConfig:viewMoreConfig];
        [self setViewSettingsConfig:viewSettingsConfig];
        [self setTopToolbarConfig:topToolbarConfig];
        [self setBottomToolbarConfig:bottomToolbarConfig];
        
        self.pdfViewCtrl.extensionsManager = self.extensionsManager;
        [self wrapTopToolbar];
        self->topToolbarVerticalConstraints = @[];
        
        NSURL *targetURL = nil;
        if (targetURL == nil) {
            targetURL = [self fileFromDocumentsDirectoryURL:src];
        }
        
        if (targetURL == nil) {
            [self showError:@"file not found in Document directory!"];
        }else{
            __weak typeof(self) weakSelf = self;
            [self.pdfViewCtrl openDoc:targetURL.path password:password completion:^(FSErrorCode error) {
                if (error == FSErrSuccess) {
                    if (!weakSelf.rootViewController.presentingViewController) {
                        [[[UIApplication sharedApplication].delegate window].rootViewController presentViewController:weakSelf.rootViewController animated:YES completion:^{

                        }];
                    }
                } else if (error == FSErrDeviceLimitation) {
                    [weakSelf showError:@"Exceeded the limit on the number of devices allowed"];
                } else if (error == FSErrCanNotGetUserToken) {
                    [weakSelf showError:@"Please Sign in first"];
                } else if (error == FSErrInvalidLicense) {
                    [weakSelf showError:@"You are not authorized to use this add-on module， please contact us for upgrading your license. "];
                } else {
                    [weakSelf showError:@"Failed to open the document"];
                }
            }];
            
            self.extensionsManager.goBack = ^{
                [weakSelf.rootViewController dismissViewControllerAnimated:YES completion:nil];
            };
        }
    });
}

-(void)showError:(NSString *)errMsg {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Error message"
                                                                   message:errMsg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * action) {
                                                              //响应事件
                                                              NSLog(@"action = %@", action);
                                                          }];
    
    [alert addAction:defaultAction];
    
    UIViewController *rootController = UIApplication.sharedApplication.delegate.window.rootViewController;
    [rootController presentViewController:alert animated:YES completion:nil];
    
}

- (NSURL *)fileFromDocumentsDirectoryURL:(NSString *) filename {
    if (filename.length == 0 ) {
        return nil;
    }
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    if (documentsDirectory == nil) {
        return nil;
    }
    NSString *filePath = [documentsDirectory stringByAppendingPathComponent: filename];
    if(![[NSFileManager defaultManager] fileExistsAtPath: filePath]) {
        return nil;
    }
    return [NSURL fileURLWithPath:filePath];
}

- (FSClientInfo *)getClientInfo {
    FSClientInfo *client_info = [[FSClientInfo alloc] init];
    client_info.device_id = [[UIDevice currentDevice] identifierForVendor].UUIDString;
    client_info.device_name = [UIDevice currentDevice].name;
    client_info.device_model = [[UIDevice currentDevice] model];
    client_info.mac_address = @"mac_address";
    client_info.os = [NSString stringWithFormat:@"%@ %@",
                      [[UIDevice currentDevice] systemName], [[UIDevice currentDevice] systemVersion]];
    client_info.product_name = @"RDK";
    client_info.product_vendor = @"Foxit";
    client_info.product_version = @"5.2.0";
    client_info.product_language = [[NSLocale preferredLanguages] objectAtIndex:0];
    
    return client_info;
}

//panelConfig
- (void) setPanelConfig: (NSDictionary *) config
{
    _panelConfig = config;
    
    if (_panelConfig != NULL) {
        id val = [_panelConfig objectForKey:@"readingBookmark"] ;
        
        if (val != NULL) {
            [self.extensionsManager.panelController setPanelHidden:![val boolValue] type:FSPanelTypeReadingBookmark];
        }
        
        val = [_panelConfig objectForKey:@"outline"] ;
        
        if (val != NULL) {
            [self.extensionsManager.panelController setPanelHidden:![val boolValue] type:FSPanelTypeOutline];
        }
        
        val = [_panelConfig objectForKey:@"annotation"] ;
        
        if (val != NULL) {
            [self.extensionsManager.panelController setPanelHidden:![val boolValue] type:FSPanelTypeAnnotation];
        }
        
        val = [_panelConfig objectForKey:@"attachments"] ;
        
        if (val != NULL) {
            [self.extensionsManager.panelController setPanelHidden:![val boolValue] type:FSPanelTypeAttachment];
        }
        
        val = [_panelConfig objectForKey:@"signature"] ;
        
        if (val != NULL) {
            [self.extensionsManager.panelController setPanelHidden:![val boolValue] type:FSPanelTypeDigitalSignature];
        }
    }
}

//viewMoreConfig
- (void) setViewMoreConfig: (NSDictionary *) config
{
    _viewMoreConfig = config;
    
    if (_viewMoreConfig != NULL) {
        NSDictionary *groupConfig = [_viewMoreConfig objectForKey:@"groupFile"];
        
        if (groupConfig != NULL) {
            [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_FILE hidden:NO];
            id val = [groupConfig objectForKey:@"fileInfo"];
            if (val) {
                [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_FILE andItemTag:TAG_ITEM_FILEINFO hidden:![val boolValue]];
            }
            val = [groupConfig objectForKey:@"reduceFileSize"];
            if (val) {
                [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_FILE andItemTag:TAG_ITEM_REDUCEFILESIZE hidden:![val boolValue]];
            }
            val = [groupConfig objectForKey:@"wirelessPrint"];
            if (val) {
                [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_FILE andItemTag:TAG_ITEM_WIRELESSPRINT hidden:![val boolValue]];
            }
            val = [groupConfig objectForKey:@"crop"];
            if (val) {
                [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_FILE andItemTag:TAG_ITEM_SCREENCAPTURE hidden:![val boolValue]];
            }
            
        }
        
        groupConfig = [_viewMoreConfig objectForKey:@"groupProtect"] ;
        
        if (groupConfig != NULL) {
            [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_PROTECT hidden:NO];
            id val = [groupConfig objectForKey:@"password"];
            if (val) {
                [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_PROTECT andItemTag:TAG_ITEM_PASSWORD hidden:![val boolValue]];
            }
        }
        
        groupConfig = [_viewMoreConfig objectForKey:@"groupComment"] ;
        
        if (groupConfig != NULL) {
            [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_COMMENT hidden:NO];
            id val = [groupConfig objectForKey:@"importComment"];
            if (val) {
                [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_COMMENT andItemTag:TAG_ITEM_IMPORTCOMMENT hidden:![val boolValue]];
            }
            val = [groupConfig objectForKey:@"exportComment"];
            if (val) {
                [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_COMMENT andItemTag:TAG_ITEM_EXPORTCOMMENT hidden:![val boolValue]];
            }
        }
        
        groupConfig = [_viewMoreConfig objectForKey:@"groupForm"] ;
        
        if (groupConfig != NULL) {
            [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_FORM hidden:NO];
            id val = [groupConfig objectForKey:@"createForm"];
            if (val) {
                [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_FORM andItemTag:TAG_ITEM_CREATEFORM hidden:![val boolValue]];
            }
            
            val = [groupConfig objectForKey:@"resetForm"];
            if (val) {
                [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_FORM andItemTag:TAG_ITEM_RESETFORM hidden:![val boolValue]];
            }
            
            val = [groupConfig objectForKey:@"importForm"];
            if (val) {
                [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_FORM andItemTag:TAG_ITEM_IMPORTFORM hidden:![val boolValue]];
            }
            val = [groupConfig objectForKey:@"exportForm"];
            if (val) {
                [self.extensionsManager.more setMoreViewItemHiddenWithGroup:TAG_GROUP_FORM andItemTag:TAG_ITEM_EXPORTFORM hidden:![val boolValue]];
            }
        }
        
    }
}

//view Settings config
- (void) setViewSettingsConfig: (NSDictionary *) config
{
    _viewSettingsConfig = config;
    
    if (_viewSettingsConfig != NULL) {
        id val = [_viewSettingsConfig objectForKey:@"single"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:SINGLE hidden:![val boolValue]];
        }
        
        val = [_viewSettingsConfig objectForKey:@"continuous"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:CONTINUOUS hidden:![val boolValue]];
        }
        
        val = [_viewSettingsConfig objectForKey:@"facingPage"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:DOUBLEPAGE hidden:![val boolValue]];
        }
        
        val = [_viewSettingsConfig objectForKey:@"coverPage"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:COVERPAGE hidden:![val boolValue]];
        }
        
        val = [_viewSettingsConfig objectForKey:@"thumbnail"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:THUMBNAIL hidden:![val boolValue]];
        }
        
        val = [_viewSettingsConfig objectForKey:@"reflow"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:REFLOW hidden:![val boolValue]];
        }
        
        val = [_viewSettingsConfig objectForKey:@"cropPage"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:CROPPAGE hidden:![val boolValue]];
        }
        
        val = [_viewSettingsConfig objectForKey:@"screenLock"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:LOCKSCREEN hidden:![val boolValue]];
        }
        
        val = [_viewSettingsConfig objectForKey:@"brightness"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:BRIGHTNESS hidden:![val boolValue]];
        }
        val = [_viewSettingsConfig objectForKey:@"nightMode"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:NIGHTMODE hidden:![val boolValue]];
        }
        
        val = [_viewSettingsConfig objectForKey:@"panZoom"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:PANZOOM hidden:![val boolValue]];
        }
        
        val = [_viewSettingsConfig objectForKey:@"fitPage"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:FITPAGE hidden:![val boolValue]];
        }
        
        val = [_viewSettingsConfig objectForKey:@"fitWidth"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:FITWIDTH hidden:![val boolValue]];
        }
        
        val = [_viewSettingsConfig objectForKey:@"rotate"] ;
        if (val != NULL) {
            [self.extensionsManager.settingBar setItem:ROTATE hidden:![val boolValue]];
        }
        
    }
}

- (void) setTopToolbarConfig: (NSDictionary *) config
{
    _topToolbarConfig = config;
    
    if (_topToolbarConfig != NULL) {
        id val = [_topToolbarConfig objectForKey:@"more"] ;
        
        if (val != NULL) {
            [self.extensionsManager setToolbarItemHiddenWithTag:FS_TOPBAR_ITEM_MORE_TAG hidden:![val boolValue]];
        }
        
        val = [_topToolbarConfig objectForKey:@"back"] ;
        
        if (val != NULL) {
            [self.extensionsManager setToolbarItemHiddenWithTag:FS_TOPBAR_ITEM_BACK_TAG hidden:![val boolValue]];
        }
        
        val = [_topToolbarConfig objectForKey:@"bookmark"] ;
        
        if (val != NULL) {
            [self.extensionsManager setToolbarItemHiddenWithTag:FS_TOPBAR_ITEM_BOOKMARK_TAG hidden:![val boolValue]];
        }
        
        val = [_topToolbarConfig objectForKey:@"search"] ;
        
        if (val != NULL) {
            [self.extensionsManager setToolbarItemHiddenWithTag:FS_TOPBAR_ITEM_SEARCH_TAG hidden:![val boolValue]];
        }
    }
}

- (void) setBottomToolbarConfig: (NSDictionary *) config
{
    _bottomToolbarConfig = config;
    
    if (_bottomToolbarConfig != NULL) {
        id val = [_bottomToolbarConfig objectForKey:@"annot"] ;
        
        if (val != NULL) {
            [self.extensionsManager setToolbarItemHiddenWithTag:FS_BOTTOMBAR_ITEM_ANNOT_TAG hidden:![val boolValue]];
        }
        
        val = [_bottomToolbarConfig objectForKey:@"panel"] ;
        
        if (val != NULL) {
            [self.extensionsManager setToolbarItemHiddenWithTag:FS_BOTTOMBAR_ITEM_PANEL_TAG hidden:![val boolValue]];
        }
        
        val = [_bottomToolbarConfig objectForKey:@"readmore"] ;
        
        if (val != NULL) {
            [self.extensionsManager setToolbarItemHiddenWithTag:FS_BOTTOMBAR_ITEM_READMODE_TAG hidden:![val boolValue]];
        }
        
        val = [_bottomToolbarConfig objectForKey:@"signature"] ;
        
        if (val != NULL) {
            [self.extensionsManager setToolbarItemHiddenWithTag:FS_BOTTOMBAR_ITEM_SIGNATURE_TAG hidden:![val boolValue]];
        }
    }
}

// MARK: - UIExtensionsManagerDelegate
#pragma mark - UIExtensionsManagerDelegate
-(BOOL)uiextensionsManager:(UIExtensionsManager *)uiextensionsManager openNewDocAtPath:(NSString *)path{
    FSPDFDoc *doc = [[FSPDFDoc alloc] initWithPath:path];
    if (FSErrSuccess == [doc load:nil]) {
        __weak typeof(self) weakSelf = self;
        [self.pdfViewCtrl openDoc:path
                         password:nil
                       completion:^(FSErrorCode error) {
                           if (error == FSErrSuccess) {
                               if (weakSelf.rootViewController.presentingViewController) {
                                    [weakSelf.rootViewController dismissViewControllerAnimated:NO completion:nil];
                               }
                               [[[UIApplication sharedApplication].delegate window].rootViewController presentViewController:weakSelf.rootViewController animated:NO completion:^{

                               }];
                           } else if (error == FSErrDeviceLimitation) {
                               [weakSelf showError:@"Exceeded the limit on the number of devices allowed"];
                           } else if (error == FSErrCanNotGetUserToken) {
                               [weakSelf showError:@"Please Sign in first"];
                           } else if (error == FSErrInvalidLicense) {
                               [weakSelf showError:@"You are not authorized to use this add-on module， please contact us for upgrading your license. "];
                           } else {
                               [weakSelf showError:@"Failed to open the document"];
                           }
                       }];
        return YES;
    }else{
        return NO;
    }
}

- (void)uiextensionsManager:(UIExtensionsManager *)uiextensionsManager setTopToolBarHidden:(BOOL)hidden {
    UIToolbar *topToolbar = self.extensionsManager.topToolbar;
    UIView *topToolbarWrapper = topToolbar.superview;
    id topGuide = self.pdfViewController.topLayoutGuide;
    assert(topGuide);
    
    [self.pdfViewCtrl removeConstraints:topToolbarVerticalConstraints];
    if (!hidden) {
        NSMutableArray *contraints = @[].mutableCopy;
        [contraints addObjectsFromArray:
         [NSLayoutConstraint constraintsWithVisualFormat:@"V:[topGuide]-0-[topToolbar(44)]"
                                                 options:0
                                                 metrics:nil
                                                   views:NSDictionaryOfVariableBindings(topToolbar, topGuide)]];
        [contraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[topToolbarWrapper]"
                                                                                options:0
                                                                                metrics:nil
                                                                                  views:NSDictionaryOfVariableBindings(topToolbarWrapper)]];
        topToolbarVerticalConstraints = contraints;
        
    } else {
        topToolbarVerticalConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:[topToolbarWrapper]-0-[topGuide]"
                                                                                options:0
                                                                                metrics:nil
                                                                                  views:NSDictionaryOfVariableBindings(topToolbarWrapper, topGuide)];
    }
    [self.pdfViewCtrl addConstraints:topToolbarVerticalConstraints];
    [UIView animateWithDuration:0.3
                     animations:^{
                         [self.pdfViewCtrl layoutIfNeeded];
                     }];
}

- (void)wrapTopToolbar {
    // let status bar be translucent. top toolbar is top layout guide (below status bar), so we need a wrapper to cover the status bar.
    UIToolbar *topToolbar = self.extensionsManager.topToolbar;
    [topToolbar setTranslatesAutoresizingMaskIntoConstraints:NO];
    
    UIView *topToolbarWrapper = [[UIToolbar alloc] init];
    [topToolbarWrapper setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.pdfViewCtrl insertSubview:topToolbarWrapper belowSubview:topToolbar];
    [topToolbarWrapper addSubview:topToolbar];
    
    [self.pdfViewCtrl addConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[topToolbarWrapper]-0-|"
                                             options:0
                                             metrics:nil
                                               views:NSDictionaryOfVariableBindings(topToolbarWrapper)]];
    [topToolbarWrapper addConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[topToolbar]-0-|"
                                             options:0
                                             metrics:nil
                                               views:NSDictionaryOfVariableBindings(topToolbar)]];
    [topToolbarWrapper addConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"V:[topToolbar]-0-|"
                                             options:0
                                             metrics:nil
                                               views:NSDictionaryOfVariableBindings(topToolbar)]];
}

// MARK: - IDocEventListener
- (void)onDocOpened:(FSPDFDoc *)document error:(int)error {
    
}

- (void)onDocClosed:(FSPDFDoc *)document error:(int)error {
    
}

#pragma mark - rotate event

- (void)orientationDidChange{
    UIDeviceOrientation currentOri = [[UIDevice currentDevice] orientation];
    [self.extensionsManager didRotateFromInterfaceOrientation:(UIInterfaceOrientation)currentOri];
}

@end

@implementation PDFNavigationController
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return !self.extensionsManager.isScreenLocked;
}

- (BOOL)shouldAutorotate {
    return !self.extensionsManager.isScreenLocked;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

@end
