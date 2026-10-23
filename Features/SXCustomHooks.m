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
static NSString *SXSignatureKey(const char *encoding) {
 NSMutableString *key=[NSMutableString string];
 for(const char *c=encoding;c && *c;c++) if(*c<'0'||*c>'9') [key appendFormat:@"%c",*c];
 return key;
}
static void sx_customNoopVoid(id self,SEL _cmd) {}
static BOOL sx_customNoopBool(id self,SEL _cmd) {return NO;}
static void sx_customNoopVoidArg(id self,SEL _cmd,id arg) {}
static BOOL sx_customNoopBoolArg(id self,SEL _cmd,id arg) {return NO;}
@implementation SXCustomHooks
+ (NSArray<NSString *> *)adHookEntries {return [NSUserDefaults.standardUserDefaults arrayForKey:kSXAdHookDefaultsKey]?:@[];}
+ (NSArray<NSString *> *)viewHookEntries {return [NSUserDefaults.standardUserDefaults arrayForKey:kSXViewHookDefaultsKey]?:@[];}
+ (void)addAdHookEntry:(NSString *)entry {
 NSMutableArray *list=[[self adHookEntries] mutableCopy];
 if(entry.length && ![list containsObject:entry]) {[list addObject:entry];[NSUserDefaults.standardUserDefaults setObject:list forKey:kSXAdHookDefaultsKey];}
}
+ (void)addViewHookEntry:(NSString *)entry {
 NSMutableArray *list=[[self viewHookEntries] mutableCopy];
 if(entry.length && ![list containsObject:entry]) {[list addObject:entry];[NSUserDefaults.standardUserDefaults setObject:list forKey:kSXViewHookDefaultsKey];}
}
+ (void)removeAdHookEntryAtIndex:(NSUInteger)index {
 NSMutableArray *list=[[self adHookEntries] mutableCopy];
 if(index<list.count){[list removeObjectAtIndex:index];[NSUserDefaults.standardUserDefaults setObject:list forKey:kSXAdHookDefaultsKey];}
}
+ (void)removeViewHookEntryAtIndex:(NSUInteger)index {
 NSMutableArray *list=[[self viewHookEntries] mutableCopy];
 if(index<list.count){[list removeObjectAtIndex:index];[NSUserDefaults.standardUserDefaults setObject:list forKey:kSXViewHookDefaultsKey];}
}
+ (void)install {
 if([SXSettings shared].disableAds) for(NSString *entry in [self adHookEntries]) [self applyEntry:entry label:@"ad"];
 if([SXSettings shared].invisibleViewing) for(NSString *entry in [self viewHookEntries]) [self applyEntry:entry label:@"view"];
}
+ (void)applyEntry:(NSString *)entry label:(NSString *)label {
 NSRange dot=[entry rangeOfString:@"."];
 if(dot.location==NSNotFound){[SXHook recordGap:label reason:[NSString stringWithFormat:@"malformed entry: %@",entry]];return;}
 NSString *className=[entry substringToIndex:dot.location];
 NSString *selectorName=[entry substringFromIndex:dot.location+1];
 if(!className.length||!selectorName.length){[SXHook recordGap:label reason:[NSString stringWithFormat:@"malformed entry: %@",entry]];return;}
 Class cls=NSClassFromString(className);
 if(!cls){[self deferApplyEntry:entry label:label className:className];return;}
 SEL sel=NSSelectorFromString(selectorName);
 Method method=class_getInstanceMethod(cls,sel);
 if(!method){[SXHook recordGap:label reason:[NSString stringWithFormat:@"%@ has no method %@",className,selectorName]];return;}
 const char *encoding=method_getTypeEncoding(method);
 NSString *sig=SXSignatureKey(encoding);
 NSUInteger argCount=[selectorName componentsSeparatedByString:@":"].count-1;
 IMP replacement=NULL;
 if(argCount==0 && [sig isEqualToString:@"v@:"]) replacement=(IMP)sx_customNoopVoid;
 else if(argCount==0 && ([sig isEqualToString:@"B@:"]||[sig isEqualToString:@"c@:"])) replacement=(IMP)sx_customNoopBool;
 else if(argCount==1 && [sig isEqualToString:@"v@:@"]) replacement=(IMP)sx_customNoopVoidArg;
 else if(argCount==1 && ([sig isEqualToString:@"B@:@"]||[sig isEqualToString:@"c@:@"])) replacement=(IMP)sx_customNoopBoolArg;
 else {[SXHook recordGap:label reason:[NSString stringWithFormat:@"%@ unsupported shape for %@ (sig %@, %lu args)",className,selectorName,sig,(unsigned long)argCount]];return;}
 class_replaceMethod(cls,sel,replacement,encoding);
 SXLog("%@ hook installed: %@.%@",label,className,selectorName);
}
+ (void)deferApplyEntry:(NSString *)entry label:(NSString *)label className:(NSString *)className {
 __block id observer=[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
 if(NSClassFromString(className)){[self applyEntry:entry label:label];[[NSNotificationCenter defaultCenter] removeObserver:observer];}
 }];
}
+ (void)scanForCandidatesMatching:(NSString *)keyword {
 if(!keyword.length)return;
 NSString *needle=keyword.lowercaseString;
 NSString *ownImage=[NSBundle.mainBundle executablePath];
 unsigned int count=0;Class *classes=objc_copyClassList(&count);NSUInteger hits=0;
 for(unsigned int i=0;i<count;i++){
 Class cls=classes[i];const char *imageName=class_getImageName(cls);if(!imageName)continue;
 NSString *image=@(imageName);
 if(![image hasPrefix:[ownImage stringByDeletingLastPathComponent]])continue;
 NSString *name=NSStringFromClass(cls);
 if([name.lowercaseString rangeOfString:needle].location==NSNotFound)continue;
 NSMutableArray<NSString *> *selectors=[NSMutableArray array];unsigned int methodCount=0;
 Method *methods=class_copyMethodList(cls,&methodCount);
 for(unsigned int j=0;j<methodCount;j++)[selectors addObject:NSStringFromSelector(method_getName(methods[j]))];
 free(methods);SXLog("scan[%@]: %@ -- %@",keyword,name,[selectors componentsJoinedByString:@", "]);hits++;
 }
 free(classes);
 if(!hits)SXLog("scan[%@]: no matching classes in the app's own bundle/frameworks",keyword);
}
@end
