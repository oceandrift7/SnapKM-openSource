// SnapKM — ©2026 X (@i5aaaald). جميع الحقوق محفوظة.
// SPDX-License-Identifier: MIT
//
// SnapKM — entry point.
//
// Reconstructed by X (@i5aaaald) from the observable interface of a third-party
// Snapchat tweak. No code was copied from the original binary; behaviour was inferred
// from published interface metadata and is tagged CONFIRMED / INFERRED / UNKNOWN in
// SPEC.md.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "Shadow/SXLog.h"
#import "Shadow/SXSettings.h"
#import "Shadow/SXSettingsViewController.h"

#import "Features/SXFeatureGate.h"
#import "Features/SXPrivacy.h"
#import "Features/SXSaveMedia.h"
#import "Features/SXLogs.h"
#import "Features/SXLocationSpoof.h"
#import "Features/SXAntiDetect.h"
#import "Features/SXCustomHooks.h"

#pragma mark - Feature registry

/// Declared before any hook runs so `SXFeatureGate` fails closed for any name that was
/// never registered.
static void SXRegisterFeatures(void) {
  [SXFeatureGate registerFeature:@"privacy" defaultEnabled:YES];
  [SXFeatureGate registerFeature:@"save_media" defaultEnabled:YES];
  [SXFeatureGate registerFeature:@"location_spoof" defaultEnabled:YES];
  [SXFeatureGate registerFeature:@"anti_detect" defaultEnabled:YES];
  [SXFeatureGate registerFeature:@"custom_hooks" defaultEnabled:YES];
}

static void SXInstallFeatures(void) {
  if ([SXFeatureGate isEnabled:@"privacy"])
    [SXPrivacy install];
  if ([SXFeatureGate isEnabled:@"save_media"])
    [SXSaveMedia install];
  if ([SXFeatureGate isEnabled:@"location_spoof"])
    [SXLocationSpoof install];
  if ([SXFeatureGate isEnabled:@"anti_detect"])
    [SXAntiDetect install];
  // disableAds / invisibleViewing: user-supplied Class.selector entries, validated
  // and installed by SXCustomHooks -- see its header for why these aren't
  // hardcoded. A no-op when both entry lists are empty, which they are by default.
  if ([SXFeatureGate isEnabled:@"custom_hooks"])
    [SXCustomHooks install];
}

#pragma mark - Settings entry point

/// Three-finger long press anywhere in the app opens the panel. Snapchat's UI is a
/// custom paged camera/chat stack with no stable navigation bar to attach a button to,
/// and its launch callbacks have already run by the time a tweak can react, so a window
/// level gesture is the one entry point that does not depend on either.
///
/// A dedicated subclass lets the installer recognise its own recogniser and stay
/// idempotent across repeated activations.
@interface SXEntryGesture : UILongPressGestureRecognizer
@end
@implementation SXEntryGesture
@end

@interface SXSettingsEntry : NSObject
+ (instancetype)shared;
- (void)installOnWindow:(UIWindow *)window;
@end

@implementation SXSettingsEntry

+ (instancetype)shared {
  static SXSettingsEntry *shared;
  static dispatch_once_t token;
  dispatch_once(&token, ^{
    shared = [[SXSettingsEntry alloc] init];
  });
  return shared;
}

- (void)installOnWindow:(UIWindow *)window {
  if (window == nil)
    return;
  for (UIGestureRecognizer *existing in window.gestureRecognizers) {
    if ([existing isKindOfClass:[SXEntryGesture class]])
      return;
  }

  SXEntryGesture *gesture =
      [[SXEntryGesture alloc] initWithTarget:self action:@selector(handle:)];
  gesture.numberOfTouchesRequired = 3;
  gesture.minimumPressDuration = 0.8;
  // Must never swallow Snapchat's own touches.
  gesture.cancelsTouchesInView = NO;
  gesture.delaysTouchesBegan = NO;
  gesture.delaysTouchesEnded = NO;
  [window addGestureRecognizer:gesture];
  SXLog("settings gesture installed (3-finger long press)");
}

- (void)handle:(UILongPressGestureRecognizer *)gesture {
  if (gesture.state != UIGestureRecognizerStateBegan)
    return;
  [SXSettingsViewController presentFrom:[SXSettingsViewController topViewController]];
}

@end

static UIWindow *SXActiveWindow(void) {
  UIApplication *app = UIApplication.sharedApplication;
  for (UIScene *scene in app.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]])
      continue;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    if (windowScene.activationState != UISceneActivationStateForegroundActive)
      continue;
    for (UIWindow *window in windowScene.windows) {
      if (window.isKeyWindow)
        return window;
    }
    if (windowScene.windows.firstObject)
      return windowScene.windows.firstObject;
  }
  return nil;
}

static void SXTryInstallEntry(void) {
  [[SXSettingsEntry shared] installOnWindow:SXActiveWindow()];
}

static void SXInstallSettingsEntryPoint(void) {
  // Activation can fire many times and the first one may precede the key window, so
  // try on every activation. The installer is idempotent.
  [[NSNotificationCenter defaultCenter]
      addObserverForName:UIApplicationDidBecomeActiveNotification
                  object:nil
                   queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *note) {
                SXTryInstallEntry();
              }];

  // Covers a tweak that loads after the app is already active.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   SXTryInstallEntry();
                 });
}

#pragma mark - Bootstrap

__attribute__((constructor)) static void SXBootstrap(void) {
  @autoreleasepool {
    SXLog("%@ starting -- (c)2026 X (@i5aaaald)",
          NSBundle.mainBundle.bundleIdentifier ?: @"Snapchat");

    SXRegisterFeatures();

    // One runloop turn so Snapchat finishes its own launch and the classes the hooks
    // target are registered. The hooks themselves poll, so a late class is fine.
    dispatch_async(dispatch_get_main_queue(), ^{
      SXInstallFeatures();
      SXInstallSettingsEntryPoint();
    });
  }
}