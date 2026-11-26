/**
 * This file is part of Darling.
 *
 * Copyright (C) 2021 Darling developers
 *
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Darling is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef _XPC_OBJECTS_BUNDLE_H_
#define _XPC_OBJECTS_BUNDLE_H_

#import <xpc/objects/base.h>

#include <dispatch/dispatch.h>

XPC_IGNORE_DUPLICATE_PROTOCOL_PUSH;
XPC_CLASS_DECL(bundle);
XPC_IGNORE_DUPLICATE_PROTOCOL_POP;

@class XPC_CLASS(string);
@class XPC_CLASS(dictionary);
@class XPC_CLASS(array);

OS_ENUM(xpc_bundle_subdirectory_type, uint8_t,
	xpc_bundle_subdirectory_type_invalid,
	xpc_bundle_subdirectory_type_xpc_services,
);

struct xpc_bundle_s {
	struct xpc_object_s base;
	XPC_CLASS(string)* bundle_path;
	XPC_CLASS(string)* executable_path;
	XPC_CLASS(dictionary)* info_dictionary;
	XPC_CLASS(array)* services;
	dispatch_once_t resolve_once;
	int error;
	bool is_framework;
};

@interface XPC_CLASS_INTERFACE(bundle)

// this API is modeled after NSBundle
// (but we've added lots of non-NSBundle extensions)

// NOTE: differs from NSBundle by returning a new bundle every time it's called
@property(class, readonly, copy) XPC_CLASS(bundle)* mainBundle;

@property(strong) XPC_CLASS(string)* bundlePath;
@property(strong) XPC_CLASS(string)* executablePath;
@property(strong) XPC_CLASS(dictionary)* infoDictionary;

/**
 * The error code encountered while resolving the bundle.
 */
@property(assign) int error;

/**
 * `YES` if this is a bundle for a framework, `NO` otherwise.
 */
@property(readonly) BOOL isFramework;

/**
 * The path to the bundle's `Info.plist`.
 */
@property(readonly) XPC_CLASS(string)* infoPath;

/**
 * Checks whether the given path points to the root of a bundle.
 */
+ (BOOL)pathIsBundleRoot: (XPC_CLASS(string)*)path;

/**
 * Automatically determines the bundle root path from the given path.
 * If the given path does not point to a path within a bundle, returns `nil`.
 */
+ (XPC_CLASS(string)*)bundleRootFromPath: (XPC_CLASS(string)*)path;

- (instancetype)initWithPath: (XPC_CLASS(string)*)path;

- (XPC_CLASS(string)*)pathForResource: (const char*)name ofType: (const char*)type;

/**
 * Returns the full path to a subdirectory of the given type, if present, or `nil` otherwise.
 */
- (XPC_CLASS(string)*)pathForSubdirectoryOfType: (xpc_bundle_subdirectory_type_t)type;

/**
 * Resolves certain components of the bundle's information synchronously. This method (or `resolveOnQueue:callbackQueue:callback:`) must be called before the bundle is used.
 */
- (void)resolve;

/**
 * Resolves certain components of the bundle's information asynchronously. This method (or `resolve`) must be called before the bundle is used.
 */
- (void)resolveOnQueue: (dispatch_queue_t)resolutionQueue callbackQueue: (dispatch_queue_t)callbackQueue callback: (void(^)(void))callback;

@end

/**
 * Watches for loaded frameworks that hold XPC services (an XPCServices
 * directory next to the framework's binary). Called once, at initialization.
 */
void xpc_bundle_services_init(void);

/**
 * Has launchd add the XPC services of the frameworks loaded so far to the
 * process's domain, so a connection can look them up by name.
 */
void xpc_bundle_services_register_loaded(void);

#endif // _XPC_OBJECTS_BUNDLE_H_
