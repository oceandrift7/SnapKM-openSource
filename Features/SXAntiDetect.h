// SnapKM — ©2026 X (@i5aaaald). جميع الحقوق محفوظة.
// SPDX-License-Identifier: MIT

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Jailbreak / tampering probe hiding.
///
/// SCOPE, stated plainly: this hides the probe list from **Objective-C level**
/// checks — `NSFileManager` existence checks and `-[UIApplication canOpenURL:]` for
/// jailbreak app URL schemes, which is how the large majority of published detection
/// code actually looks. It does not intercept the raw libc calls (`stat`, `access`,
/// `open`, `fork`) a check could use instead. Reaching those requires inline function
/// hooking, which on arm64e means forging pointer-authenticated trampolines with no
/// device to test against — a wrong implementation there crashes the host outright,
/// which is worse than a detection check succeeding. That remains a documented gap,
/// not a silent one: `existingProbes` still reports what raw filesystem access would
/// see, so the gap is visible in the log viewer rather than assumed fixed.
@interface SXAntiDetect : NSObject

+ (void)install;

/// The probe list, recovered verbatim from the shipped binary's string table.
+ (NSArray<NSString *> *)probePaths;

/// Paths from `probePaths` that currently exist on this device, as raw filesystem
/// access would see them — i.e. what remains visible after `install` because it is
/// below the Objective-C layer this class covers.
+ (NSArray<NSString *> *)existingProbes;

@end

NS_ASSUME_NONNULL_END
