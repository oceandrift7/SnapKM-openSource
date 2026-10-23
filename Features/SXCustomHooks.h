// SnapKM — ©2026 X (@i5aaaald). جميع الحقوق محفوظة.
// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface SXCustomHooks : NSObject
+ (void)install;
+ (NSArray<NSString *> *)adHookEntries;
+ (NSArray<NSString *> *)viewHookEntries;
+ (void)addAdHookEntry:(NSString *)entry;
+ (void)addViewHookEntry:(NSString *)entry;
+ (void)removeAdHookEntryAtIndex:(NSUInteger)index;
+ (void)removeViewHookEntryAtIndex:(NSUInteger)index;
+ (void)scanForCandidatesMatching:(NSString *)keyword;
@end
NS_ASSUME_NONNULL_END
