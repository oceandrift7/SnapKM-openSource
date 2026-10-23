// SnapKM — ©2026 X (@i5aaaald). جميع الحقوق محفوظة.
// SPDX-License-Identifier: MIT

#import "SXAntiDetect.h"
#import <UIKit/UIKit.h>
#import "../Shadow/SXHook.h"
#import "../Shadow/SXLog.h"
#import "../Shadow/SXSettings.h"

@implementation SXAntiDetect

+ (void)install {
  if (![SXSettings shared].cloakAntiDetect) {
    SXLog("cloak anti-detection disabled");
    return;
  }

  // Reported once, not per lookup: a probe that logs on every call would flood the
  // log viewer and cost more than the check.
  NSArray<NSString *> *found = [self existingProbes];
  if (found.count > 0)
    SXLog("tampering indicators present below the Objective-C layer: %@",
          [found componentsJoinedByString:@", "]);
  else
    SXLog("no tampering indicators found");

  [SXHook installWhenAvailable:@"NSFileManager"
                         owner:[SXAntiDetect class]
                      original:@selector(fileExistsAtPath:)
                   replacement:@selector(sx_fileExistsAtPath:)
                       timeout:5.0];
  [SXHook installWhenAvailable:@"NSFileManager"
                         owner:[SXAntiDetect class]
                      original:@selector(fileExistsAtPath:isDirectory:)
                   replacement:@selector(sx_fileExistsAtPath:isDirectory:)
                       timeout:5.0];
  [SXHook installWhenAvailable:@"UIApplication"
                         owner:[SXAntiDetect class]
                      original:@selector(canOpenURL:)
                   replacement:@selector(sx_canOpenURL:)
                       timeout:5.0];
}

+ (NSArray<NSString *> *)probePaths {
  static NSArray<NSString *> *paths;
  static dispatch_once_t token;
  dispatch_once(&token, ^{
    paths = @[
      // Roots
      @"/.jbroot", @"/jb/", @"/var/jb", @"/var/jb/", @"/private/var/jb",
      @"/private/preboot", @"/private/preboot/",
      // Package managers
      @"/Applications/Cydia.app", @"/Applications/Filza.app", @"/Applications/Sileo.app",
      @"/Applications/Zebra.app", @"/var/lib/dpkg", @"/var/lib/apt", @"/etc/apt",
      @"/Dopamine", @"/Cryptexes/",
      // Injection frameworks
      @"/Library/Frameworks/CydiaSubstrate", @"/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
      @"/Library/MobileSubstrate", @"/Library/MobileSubstrate/",
      @"/Library/PreferenceLoader", @"/usr/lib/TweakLoader",
      // Jailbreak markers
      @"/usr/lib/libjailbreak",
      @"/usr/sbin/sshd", @"/usr/bin/ssh",
      // Shells exposed by the original's probe list
      @"/bin/bash", @"/bin/sh", @"/bin/zsh",
      // Preferences roots, both rootless and rootful
      @"/var/mobile/Library/Preferences/plist.plist",
      @"/var/jb/var/mobile/Library/Preferences/plist.plist",
      @"/var/binpack", @"/var/LIB",
    ];
  });
  return paths;
}

/// Jailbreak app URL schemes `-canOpenURL:` is commonly used to probe for.
+ (NSArray<NSString *> *)probeSchemes {
  static NSArray<NSString *> *schemes;
  static dispatch_once_t token;
  dispatch_once(&token, ^{
    schemes = @[ @"cydia", @"sileo", @"zbra", @"filza", @"activator" ];
  });
  return schemes;
}

/// True filesystem check, bypassing the hook below — used both for the diagnostic
/// listing and inside the hook itself, which must consult the real filesystem to
/// decide what to hide.
+ (BOOL)realFileExistsAtPath:(NSString *)path {
  return [NSFileManager.defaultManager fileExistsAtPath:path];
}

+ (NSArray<NSString *> *)existingProbes {
  NSMutableArray<NSString *> *found = [NSMutableArray array];
  for (NSString *path in [self probePaths]) {
    if ([self realFileExistsAtPath:path])
      [found addObject:path];
  }
  return found;
}

+ (BOOL)isProbePath:(NSString *)path {
  if (path.length == 0)
    return NO;
  for (NSString *probe in [self probePaths]) {
    if ([path isEqualToString:probe] || [path hasPrefix:probe])
      return YES;
  }
  return NO;
}

#pragma mark - Hooks

- (BOOL)sx_fileExistsAtPath:(NSString *)path {
  if ([SXSettings shared].cloakAntiDetect && [SXAntiDetect isProbePath:path]) {
    SXDebugLog("hid probe path: %@", path);
    return NO;
  }
  return [self sx_fileExistsAtPath:path];
}

- (BOOL)sx_fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
  if ([SXSettings shared].cloakAntiDetect && [SXAntiDetect isProbePath:path]) {
    SXDebugLog("hid probe path: %@", path);
    if (isDirectory != NULL)
      *isDirectory = NO;
    return NO;
  }
  return [self sx_fileExistsAtPath:path isDirectory:isDirectory];
}

- (BOOL)sx_canOpenURL:(NSURL *)url {
  if ([SXSettings shared].cloakAntiDetect) {
    NSString *scheme = url.scheme.lowercaseString;
    if (scheme != nil && [[SXAntiDetect probeSchemes] containsObject:scheme]) {
      SXDebugLog("hid URL scheme probe: %@", scheme);
      return NO;
    }
  }
  return [self sx_canOpenURL:url];
}

@end
