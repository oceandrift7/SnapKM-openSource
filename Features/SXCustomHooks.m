// SnapKM — ©2026 X (@i5aaaald). جميع الحقوق محفوظة.
// SPDX-License-Identifier: MIT

#import "SXCustomHooks.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "../Shadow/SXHook.h"
#import "../Shadow/SXLog.h"
#import "../Shadow/SXSettings.h"

static NSString *const kSXAdHookDefaultsKey = @"SnapKM.customAdHooks";
static NSString *const kSXViewHookDefaultsKey = @"SnapKM.customViewHooks";

/// Canonical, digit-stripped signatures for the four shapes this engine supports.
/// Both the modern (`B`) and legacy (`c`) BOOL encodings are accepted since which one
/// a given SDK emits isn't something this code controls.
static NSString *const kSXSig0Void = @"v@:";
static NSString *const kSXSig0BoolModern = @"B@:";
static NSString *const kSXSig0BoolLegacy = @"c@:";
static NSString *const kSXSig1Void = @"v@:@";
static NSString *const kSXSig1BoolModern = @"B@:@";
static NSString *const kSXSig1BoolLegacy = @"c@:@";

static NSString *SXSignatureKey(const char *encoding) {
  NSMutableString *key = [NSMutableString string];
  for (const char *c = encoding; c != NULL && *c != '\0'; c++) {
    if (*c < '0' || *c > '9')
      [key appendFormat:@"%c", *c];
  }
  return key;
}

static void sx_customNoopVoid(id self, SEL _cmd) {
  SXDebugLog("custom hook suppressed %@ -[%@ %@]", @"", NSStringFromClass([self class]),
             NSStringFromSelector(_cmd));
}
static BOOL sx_customNoopBool(id self, SEL _cmd) {
  return NO;
}
static void sx_customNoopVoidArg(id self, SEL _cmd, id arg) {
}
static BOOL sx_customNoopBoolArg(id self, SEL _cmd, id arg) {
  return NO;
}

@implementation SXCustomHooks

#pragma mark - Storage

+ (NSArray<NSString *> *)adHookEntries {
  return [NSUserDefaults.standardUserDefaults arrayForKey:kSXAdHookDefaultsKey] ?: @[];
}

+ (NSArray<NSString *> *)viewHookEntries {
  return [NSUserDefaults.standardUserDefaults arrayForKey:kSXViewHookDefaultsKey] ?: @[];
}

+ (void)addAdHookEntry:(NSString *)entry {
  NSMutableArray *list = [[self adHookEntries] mutableCopy];
  if (entry.length > 0 && ![list containsObject:entry]) {
    [list addObject:entry];
    [NSUserDefaults.standardUserDefaults setObject:list forKey:kSXAdHookDefaultsKey];
  }
}

+ (void)addViewHookEntry:(NSString *)entry {
  NSMutableArray *list = [[self viewHookEntries] mutableCopy];
  if (entry.length > 0 && ![list containsObject:entry]) {
    [list addObject:entry];
    [NSUserDefaults.standardUserDefaults setObject:list forKey:kSXViewHookDefaultsKey];
  }
}

+ (void)removeAdHookEntryAtIndex:(NSUInteger)index {
  NSMutableArray *list = [[self adHookEntries] mutableCopy];
  if (index < list.count) {
    [list removeObjectAtIndex:index];
    [NSUserDefaults.standardUserDefaults setObject:list forKey:kSXAdHookDefaultsKey];
  }
}

+ (void)removeViewHookEntryAtIndex:(NSUInteger)index {
  NSMutableArray *list = [[self viewHookEntries] mutableCopy];
  if (index < list.count) {
    [list removeObjectAtIndex:index];
    [NSUserDefaults.standardUserDefaults setObject:list forKey:kSXViewHookDefaultsKey];
  }
}

#pragma mark - Install

+ (void)install {
  if ([SXSettings shared].disableAds) {
    for (NSString *entry in [self adHookEntries])
      [self applyEntry:entry label:@"ad"];
  }
  if ([SXSettings shared].invisibleViewing) {
    for (NSString *entry in [self viewHookEntries])
      [self applyEntry:entry label:@"view"];
  }
}

/// `entry` is "ClassName.selector" or "ClassName.selector:" (zero or one argument).
+ (void)applyEntry:(NSString *)entry label:(NSString *)label {
  NSRange dot = [entry rangeOfString:@"."];
  if (dot.location == NSNotFound) {
    [SXHook recordGap:label reason:([NSString stringWithFormat:@"malformed entry (want Class.selector): %@", entry])];
    return;
  }
  NSString *className = [entry substringToIndex:dot.location];
  NSString *selectorName = [entry substringFromIndex:dot.location + 1];
  if (className.length == 0 || selectorName.length == 0) {
    [SXHook recordGap:label reason:([NSString stringWithFormat:@"malformed entry: %@", entry])];
    return;
  }

  Class cls = NSClassFromString(className);
  if (cls == Nil) {
    // Snapchat classes can register after this runs; retry once the class shows up,
    // same deferred pattern SXHook uses elsewhere, rather than treat a late class as
    // a permanent gap.
    [self deferApplyEntry:entry label:label className:className];
    return;
  }

  SEL sel = NSSelectorFromString(selectorName);
  Method method = class_getInstanceMethod(cls, sel);
  if (method == NULL) {
    [SXHook recordGap:label reason:([NSString stringWithFormat:@"%@ has no method %@", className, selectorName])];
    return;
  }

  const char *encoding = method_getTypeEncoding(method);
  NSString *sig = SXSignatureKey(encoding);
  NSUInteger argCount = [selectorName componentsSeparatedByString:@":"].count - 1;

  IMP replacement = NULL;
  if (argCount == 0 && [sig isEqualToString:kSXSig0Void]) {
    replacement = (IMP)sx_customNoopVoid;
  } else if (argCount == 0 &&
             ([sig isEqualToString:kSXSig0BoolModern] || [sig isEqualToString:kSXSig0BoolLegacy])) {
    replacement = (IMP)sx_customNoopBool;
  } else if (argCount == 1 && [sig isEqualToString:kSXSig1Void]) {
    replacement = (IMP)sx_customNoopVoidArg;
  } else if (argCount == 1 &&
             ([sig isEqualToString:kSXSig1BoolModern] || [sig isEqualToString:kSXSig1BoolLegacy])) {
    replacement = (IMP)sx_customNoopBoolArg;
  } else {
    [SXHook recordGap:label reason:([NSString stringWithFormat:
                           @"%@ unsupported shape for %@ (sig %@, %lu args) -- only "
                            "0/1-arg void or BOOL methods are supported",
                           className, selectorName, sig, (unsigned long)argCount])];
    return;
  }

  class_replaceMethod(cls, sel, replacement, encoding);
  SXLog("%@ hook installed: %@.%@", label, className, selectorName);
}

+ (void)deferApplyEntry:(NSString *)entry label:(NSString *)label className:(NSString *)className {
  __block id observer = [[NSNotificationCenter defaultCenter]
      addObserverForName:UIApplicationDidBecomeActiveNotification
                  object:nil
                   queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *note) {
                if (NSClassFromString(className) != Nil) {
                  [self applyEntry:entry label:label];
                  [[NSNotificationCenter defaultCenter] removeObserver:observer];
                }
              }];
}

#pragma mark - Discovery

+ (void)scanForCandidatesMatching:(NSString *)keyword {
  if (keyword.length == 0)
    return;
  NSString *needle = keyword.lowercaseString;
  NSString *ownImage = [NSBundle.mainBundle executablePath];

  unsigned int count = 0;
  Class *classes = objc_copyClassList(&count);
  NSUInteger hits = 0;
  for (unsigned int i = 0; i < count; i++) {
    Class cls = classes[i];
    const char *imageName = class_getImageName(cls);
    if (imageName == NULL)
      continue;
    // Restrict to the app's own executable and bundled frameworks -- Apple's own
    // classes would otherwise swamp the output with irrelevant matches, and this
    // tool exists to find Snapchat's own classes, not UIKit's.
    NSString *image = @(imageName);
    if (![image hasPrefix:[ownImage stringByDeletingLastPathComponent]])
      continue;

    NSString *name = NSStringFromClass(cls);
    if ([name.lowercaseString rangeOfString:needle].location == NSNotFound)
      continue;

    NSMutableArray<NSString *> *selectors = [NSMutableArray array];
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int m = 0; m < methodCount; m++)
      [selectors addObject:NSStringFromSelector(method_getName(methods[m]))];
    free(methods);

    SXLog("scan[%@]: %@ -- %@", keyword, name, [selectors componentsJoinedByString:@", "]);
    hits++;
  }
  free(classes);

  if (hits == 0)
    SXLog("scan[%@]: no matching classes in the app's own bundle/frameworks", keyword);
}

@end
