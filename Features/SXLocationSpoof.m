// SnapKM — ©2026 X (@i5aaaald). جميع الحقوق محفوظة.
// SPDX-License-Identifier: MIT

#import "SXLocationSpoof.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <string.h>
#import "../Shadow/SXHook.h"
#import "../Shadow/SXLog.h"
#import "../Shadow/SXSettings.h"

/// Nominal horizontal accuracy (metres) when there is no real fix to copy one from.
static const CLLocationAccuracy kSXNominalAccuracy = 10.0;

static BOOL SXPathIsSystem(const char *path) {
  if (path == NULL)
    return NO;
  // Rootless jailbreak paths start with /var/jb, so a tweak living under
  // /var/jb/usr/lib is correctly *not* matched by the /usr/lib prefix.
  return strncmp(path, "/System/", 8) == 0 || strncmp(path, "/usr/lib/", 9) == 0 ||
         strncmp(path, "/Library/Apple/", 15) == 0 ||
         strncmp(path, "/private/preboot/Cryptexes/", 27) == 0;
}

@implementation SXLocationSpoof

+ (void)install {
  // Property reads.
  [SXHook installWhenAvailable:@"CLLocationManager"
                         owner:[SXLocationSpoof class]
                      original:@selector(location)
                   replacement:@selector(sx_snapkm_location)
                       timeout:20.0];
  [SXHook installWhenAvailable:@"SCLocationManager"
                         owner:[SXLocationSpoof class]
                      original:@selector(location)
                   replacement:@selector(sx_snapkm_sclocation)
                       timeout:20.0];
  [SXHook installWhenAvailable:@"SCLocationManager"
                         owner:[SXLocationSpoof class]
                      original:@selector(sharedGeoLocation)
                   replacement:@selector(sx_snapkm_sharedGeoLocation)
                       timeout:20.0];

  // Delegate callbacks. The delegate is set before updates start, so the start calls are
  // the earliest point at which the delegate's class is reliably known.
  [SXHook installWhenAvailable:@"CLLocationManager"
                         owner:[SXLocationSpoof class]
                      original:@selector(startUpdatingLocation)
                   replacement:@selector(sx_snapkm_startUpdatingLocation)
                       timeout:20.0];
  [SXHook installWhenAvailable:@"CLLocationManager"
                         owner:[SXLocationSpoof class]
                      original:@selector(requestLocation)
                   replacement:@selector(sx_snapkm_requestLocation)
                       timeout:20.0];
  [SXHook installWhenAvailable:@"CLLocationManager"
                         owner:[SXLocationSpoof class]
                      original:@selector(startMonitoringSignificantLocationChanges)
                   replacement:@selector(sx_snapkm_startMonitoringSignificantLocationChanges)
                       timeout:20.0];

  SXLog("location spoof hooks requested");
}

#pragma mark - Decision

+ (nullable CLLocation *)spoofedLocationBasedOn:(nullable CLLocation *)base {
  SXSettings *settings = [SXSettings shared];
  if (!settings.spoofLocation)
    return nil;

  CLLocationCoordinate2D coordinate =
      CLLocationCoordinate2DMake(settings.spoofLatitude, settings.spoofLongitude);

  // Null Island is the "unset" value, not a destination.
  if (coordinate.latitude == 0.0 && coordinate.longitude == 0.0)
    return nil;
  if (!CLLocationCoordinate2DIsValid(coordinate))
    return nil;

  if (base == nil) {
    return [[CLLocation alloc] initWithCoordinate:coordinate
                                         altitude:0
                               horizontalAccuracy:kSXNominalAccuracy
                                 verticalAccuracy:kSXNominalAccuracy
                                        timestamp:[NSDate date]];
  }

  return [[CLLocation alloc] initWithCoordinate:coordinate
                                       altitude:base.altitude
                             horizontalAccuracy:base.horizontalAccuracy
                               verticalAccuracy:base.verticalAccuracy
                                         course:base.course
                                          speed:base.speed
                                      timestamp:base.timestamp];
}

+ (BOOL)isSystemCallerAddress:(const void *)address {
  Dl_info info;
  if (address == NULL || dladdr(address, &info) == 0)
    return YES;  // Cannot tell who is asking: the real location is the safe answer.
  return SXPathIsSystem(info.dli_fname);
}

+ (nullable CLLocation *)resolvedLocation:(nullable CLLocation *)location
                                   caller:(const void *)caller {
  if (![SXSettings shared].spoofLocation)
    return location;
  if ([self isSystemCallerAddress:caller])
    return location;
  return [self spoofedLocationBasedOn:location] ?: location;
}

+ (NSArray<CLLocation *> *)spoofedArray:(NSArray<CLLocation *> *)locations {
  if (![SXSettings shared].spoofLocation || locations.count == 0)
    return locations;
  NSMutableArray<CLLocation *> *mapped = [NSMutableArray arrayWithCapacity:locations.count];
  for (CLLocation *location in locations)
    [mapped addObject:[self spoofedLocationBasedOn:location] ?: location];
  return mapped;
}

#pragma mark - Delegate hooking

/// Wraps the delegate's location callbacks with IMP-level hooks.
///
/// Delegates are arbitrary classes, often with subclass relationships, so this
/// deliberately does not use the selector-exchange scheme in `SXHook`: that scheme
/// shares one replacement selector across classes, which loops forever when a hooked
/// subclass calls `super` into a hooked parent. Capturing the original IMP in the
/// block has no such coupling — hooking both just spoofs twice, which is idempotent.
+ (void)hookDelegateClass:(Class)delegateClass {
  if (delegateClass == Nil)
    return;
  if (SXPathIsSystem(class_getImageName(delegateClass)))
    return;  // Apple's own delegates keep the real location.

  static NSMutableSet<NSString *> *done;
  static dispatch_once_t token;
  dispatch_once(&token, ^{
    done = [NSMutableSet set];
  });
  NSString *name = NSStringFromClass(delegateClass);
  @synchronized(done) {
    if ([done containsObject:name])
      return;
    [done addObject:name];
  }

  SEL modern = @selector(locationManager:didUpdateLocations:);
  Method modernMethod = class_getInstanceMethod(delegateClass, modern);
  if (modernMethod != NULL) {
    IMP original = method_getImplementation(modernMethod);
    IMP replacement = imp_implementationWithBlock(
        ^(id object, CLLocationManager *manager, NSArray<CLLocation *> *locations) {
          ((void (*)(id, SEL, CLLocationManager *, NSArray *))original)(
              object, modern, manager, [SXLocationSpoof spoofedArray:locations]);
        });
    class_replaceMethod(delegateClass, modern, replacement,
                        method_getTypeEncoding(modernMethod));
    SXLog("location delegate hooked: %@", name);
  }

  SEL legacy = @selector(locationManager:didUpdateToLocation:fromLocation:);
  Method legacyMethod = class_getInstanceMethod(delegateClass, legacy);
  if (legacyMethod != NULL) {
    IMP original = method_getImplementation(legacyMethod);
    IMP replacement = imp_implementationWithBlock(
        ^(id object, CLLocationManager *manager, CLLocation *newLocation,
          CLLocation *oldLocation) {
          CLLocation *spoofedNew = [SXLocationSpoof spoofedLocationBasedOn:newLocation];
          CLLocation *spoofedOld = oldLocation ? [SXLocationSpoof spoofedLocationBasedOn:oldLocation]
                                               : nil;
          ((void (*)(id, SEL, CLLocationManager *, CLLocation *, CLLocation *))original)(
              object, legacy, manager, spoofedNew ?: newLocation, spoofedOld ?: oldLocation);
        });
    class_replaceMethod(delegateClass, legacy, replacement,
                        method_getTypeEncoding(legacyMethod));
    SXLog("location delegate (legacy) hooked: %@", name);
  }

  if (modernMethod == NULL && legacyMethod == NULL)
    SXDebugLog("location delegate %@ implements no update callback", name);
}

+ (void)hookDelegateOf:(CLLocationManager *)manager {
  id delegate = manager.delegate;
  if (delegate != nil)
    [self hookDelegateClass:[delegate class]];
}

#pragma mark - Hook bodies
// `self` in each of these is the Snapchat/CoreLocation instance, not an SXLocationSpoof.

- (CLLocation *)sx_snapkm_location {
  const void *caller = __builtin_return_address(0);
  return [SXLocationSpoof resolvedLocation:[self sx_snapkm_location] caller:caller];
}

- (CLLocation *)sx_snapkm_sclocation {
  const void *caller = __builtin_return_address(0);
  return [SXLocationSpoof resolvedLocation:[self sx_snapkm_sclocation] caller:caller];
}

- (CLLocation *)sx_snapkm_sharedGeoLocation {
  const void *caller = __builtin_return_address(0);
  return [SXLocationSpoof resolvedLocation:[self sx_snapkm_sharedGeoLocation] caller:caller];
}

- (void)sx_snapkm_startUpdatingLocation {
  [SXLocationSpoof hookDelegateOf:(CLLocationManager *)self];
  [self sx_snapkm_startUpdatingLocation];
}

- (void)sx_snapkm_requestLocation {
  [SXLocationSpoof hookDelegateOf:(CLLocationManager *)self];
  [self sx_snapkm_requestLocation];
}

- (void)sx_snapkm_startMonitoringSignificantLocationChanges {
  [SXLocationSpoof hookDelegateOf:(CLLocationManager *)self];
  [self sx_snapkm_startMonitoringSignificantLocationChanges];
}

@end
