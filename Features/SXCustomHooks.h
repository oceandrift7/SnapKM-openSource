// SnapKM — ©2026 X (@i5aaaald). جميع الحقوق محفوظة.
// SPDX-License-Identifier: MIT

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Generic suppressor for `disableAds` and `invisibleViewing`.
///
/// Snapchat's ad and analytics class names are private, undocumented, and change
/// often enough that hardcoding them would recreate exactly the bug this build fixed
/// elsewhere: a hook that looks real but silently targets a class that no longer
/// exists. So instead of guessing names, this is a small, safe, user-editable engine:
///
///  1. `scanForCandidatesMatching:` walks the classes loaded from the app's own
///     bundle and frameworks (never system images) and logs ones whose name matches
///     a keyword, as a starting point for finding the right one on a given Snapchat
///     build. Output goes to the log viewer, Class.selector per line.
///  2. The user adds confirmed `Class.selector` entries through Settings. Each entry
///     is validated against the live method's actual signature before it is
///     installed -- SXHook's existing signature gate -- and is skipped, not crashed
///     past, on a mismatch.
///
/// Supported shapes are intentionally narrow: a zero-argument method returning void
/// or BOOL, and a one-object-argument method returning void or BOOL. That covers the
/// large majority of "suppress this call" / "hide this view" points (view lifecycle
/// methods, single-callback delegate methods) without needing a general-purpose
/// dynamic invoker, which is far harder to get right without a device to test on.
@interface SXCustomHooks : NSObject

+ (void)install;

/// User-defaults-backed entry lists, each an array of "ClassName.selector:" strings.
+ (NSArray<NSString *> *)adHookEntries;
+ (NSArray<NSString *> *)viewHookEntries;
+ (void)addAdHookEntry:(NSString *)entry;
+ (void)addViewHookEntry:(NSString *)entry;
+ (void)removeAdHookEntryAtIndex:(NSUInteger)index;
+ (void)removeViewHookEntryAtIndex:(NSUInteger)index;

/// Scans classes from the app's own bundle and frameworks for a case-insensitive
/// name match, logging `ClassName -- selector1, selector2, ...` for each hit.
/// `keyword` is matched against class names only (e.g. "ad", "sponsor", "analytics",
/// "impression"); the listed selectors are every method the class declares, so the
/// user can see which ones look like candidates without a decompiler.
+ (void)scanForCandidatesMatching:(NSString *)keyword;

@end

NS_ASSUME_NONNULL_END
