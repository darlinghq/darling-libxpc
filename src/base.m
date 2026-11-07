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

#import <xpc/objects/base.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSString.h>
#import <objc/runtime.h>
#import <xpc/xpc.h>
#import <xpc/serialization.h>

// the symbol alias for the base xpc_object class is named differently
#if !XPC_OBJC1
XPC_EXPORT struct objc_class _xpc_type_base;
_CREATE_ALIAS(OS_OBJC_CLASS_RAW_SYMBOL_NAME(XPC_CLASS(object)), "__xpc_type_base");
#endif

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(object)

XPC_CLASS_HEADER(object);

+ (instancetype)allocWithZone: (NSZone*)zone
{
	return (id)_os_object_alloc_realized([self class], [self instanceSize]);
}

_Pragma("GCC diagnostic push");
_Pragma("GCC diagnostic ignored \"-Wobjc-designated-initializers\"");
- (instancetype)init
{
	// we CANNOT call `-[super init]`.
	// libdispatch makes `init` crash on `OS_object`s.
	return self;
}
_Pragma("GCC diagnostic pop");

- (char*)xpcDescription
{
	char* string = NULL;
	asprintf(&string, "<%s: %p>", class_getName([self class]), self);
	return string;
}

- (NSString*)description
{
	Class nsstring = objc_lookUpClass("NSString");
	if (!nsstring) return nil;
	char* desc = self.xpcDescription;
	return [[[nsstring alloc] initWithBytesNoCopy: desc
	                                       length: strlen(desc)
	                                     encoding: NSUTF8StringEncoding
	                                 freeWhenDone: YES] autorelease];
}

- (BOOL)isEqual: (id)object
{
	if (![object isKindOfClass: [self class]]) {
		return NO;
	}
	return [self hash] == [object hash];
}

- (instancetype)copy
{
	return [self retain];
}

@end

@implementation XPC_CLASS(object) (XPCSerialization)

- (BOOL)serializable
{
	return NO;
}

- (NSUInteger)serializationLength
{
	return 0;
}

+ (instancetype)deserialize: (XPC_CLASS(deserializer)*)deserializer
{
	return nil;
}

- (BOOL)serialize: (XPC_CLASS(serializer)*)serializer
{
	return NO;
}

@end

//
// C API
//

XPC_EXPORT
xpc_object_t (xpc_retain)(xpc_object_t object) {
	return [object retain];
};

XPC_EXPORT
void (xpc_release)(xpc_object_t object) {
	return [object release];
};

XPC_EXPORT
xpc_object_t xpc_copy(xpc_object_t object) {
	return [object copy];
};

XPC_EXPORT
bool xpc_equal(xpc_object_t object1, xpc_object_t object2) {
	return [object1 isEqual: object2];
};

XPC_EXPORT
size_t xpc_hash(xpc_object_t object) {
	return [object hash];
};

XPC_EXPORT
char* xpc_copy_description(xpc_object_t object) {
	return [XPC_CAST(object, object) xpcDescription];
};

//
// private C API
//

XPC_EXPORT
char* xpc_copy_debug_description(xpc_object_t object) {
	// for now
	return xpc_copy_description(object);
};

XPC_EXPORT
char* xpc_copy_short_description(xpc_object_t object) {
	// for now
	return xpc_copy_description(object);
};

XPC_EXPORT
char* xpc_copy_clean_description(xpc_object_t object) {
	// for now
	return xpc_copy_description(object);
};

XPC_EXPORT
char* xpc_inspect_copy_description(xpc_object_t object, xpc_object_t another_object) {
	// returns a string that must be freed
	return NULL;
};

XPC_EXPORT
char* xpc_inspect_copy_description_local(xpc_object_t object, xpc_object_t another_object) {
	// returns a string that must be freed
	return NULL;
};

XPC_EXPORT
char* xpc_inspect_copy_short_description(xpc_object_t object, xpc_object_t another_object) {
	// returns a string that must be freed
	return NULL;
};

XPC_EXPORT
char* xpc_inspect_copy_short_description_local(xpc_object_t object, xpc_object_t another_object) {
	// returns a string that must be freed
	return NULL;
};
