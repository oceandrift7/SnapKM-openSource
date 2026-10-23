// SnapKM — ©2026 X (@i5aaaald). جميع الحقوق محفوظة.
// SPDX-License-Identifier: MIT

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Snap Map location spoof.
///
/// Location reaches an app by two routes, and both are covered:
///
///  1. Property reads — `-[CLLocationManager location]` and Snapchat's own
///     `SCLocationManager` accessors. Gated by the *calling image*: a read made from
///     Apple's own code (`/System`, `/usr/lib`) gets the real fix, a read made from
///     Snapchat or this tweak gets the spoof.
///  2. Delegate callbacks — `locationManager:didUpdateLocations:` and its legacy
///     two-location form. This is how apps normally receive fixes, so a spoof that only
///     covered (1) would leave the map showing the real position. Hooked per delegate
///     class the first time a manager starts updating, and only for delegate classes
///     that do not live in a system image.
///
/// The spoof keeps the real fix's accuracy, course, speed and timestamp and replaces
/// only the coordinate, so consumers see a plausible fix rather than a synthetic one.
@interface SXLocationSpoof : NSObject

+ (void)install;

/// A copy of `base` relocated to the configured coordinate, or nil when spoofing is off,
/// the coordinate is unset, or it is not a valid coordinate. `base` may be nil (no fix
/// yet), in which case a fresh location with a nominal accuracy is produced.
+ (nullable CLLocation *)spoofedLocationBasedOn:(nullable CLLocation *)base;

/// YES when `address` (a return address) lies in an Apple system image. Unresolvable
/// addresses report YES, so a failed lookup falls back to the real location.
+ (BOOL)isSystemCallerAddress:(const void *)address;

/// Hook body for property reads. Returns what the caller should receive.
+ (nullable CLLocation *)resolvedLocation:(nullable CLLocation *)location
                                   caller:(const void *)caller;

@end

NS_ASSUME_NONNULL_END
