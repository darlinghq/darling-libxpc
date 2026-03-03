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

#ifndef _XPC_OBJECTS_BASE_H_
#define _XPC_OBJECTS_BASE_H_

#import <os/object_private.h>
#import <objc/NSObject.h>
#import <xpc/internal_base.h>

#define __XPC_INDIRECT__
#import <xpc/base.h>

XPC_IGNORE_DUPLICATE_PROTOCOL_PUSH;
OS_OBJECT_DECL(xpc_object);
XPC_IGNORE_DUPLICATE_PROTOCOL_POP;

#define XPC_CLASS(name) OS_OBJECT_CLASS(xpc_ ## name)

#define XPC_CLASS_DECL(name) OS_OBJECT_DECL_SUBCLASS(xpc_ ## name, xpc_object)

#define XPC_CLASS_INTERFACE(name) XPC_CLASS(name) : XPC_CLASS(object) <XPC_CLASS(name)>

#define XPC_CAST(name, object) ((XPC_CLASS(name)*)object)

#define XPC_CLASS_HEADER(name) \
	OS_OBJECT_NONLAZY_CLASS_LOAD \
	+ (NSUInteger)instanceSize \
	{ \
		return sizeof(struct xpc_ ## name ## _s); \
	}

#define XPC_THIS(name) ((struct xpc_ ## name ## _s*)self)
#define XPC_THIS_DECL(name) struct xpc_ ## name ## _s* this = XPC_THIS(name)

#define XPC_WRAPPER_CLASS_DECL(name, type) \
	XPC_CLASS_DECL(name); \
	struct xpc_ ## name ## _s { \
		struct xpc_object_s base; \
		type value; \
	}; \
	@interface XPC_CLASS_INTERFACE(name) \
		@property(assign) type value; \
		- (instancetype)initWithValue: (type)value; \
	@end

#define XPC_WRAPPER_CLASS_IMPL(name, type, format) \
	XPC_CLASS_SYMBOL_DECL(name); \
	OS_OBJECT_NONLAZY_CLASS \
	@implementation XPC_CLASS(name) \
	XPC_CLASS_HEADER(name); \
	- (char*)xpcDescription \
	{ \
		char* output = NULL; \
		asprintf(&output, "<%s: " format ">", xpc_class_name(self), self.value); \
		return output; \
	} \
	- (type)value \
	{ \
		XPC_THIS_DECL(name); \
		return this->value; \
	} \
	- (void)setValue: (type)value \
	{ \
		XPC_THIS_DECL(name); \
		this->value = value; \
	} \
	- (instancetype)initWithValue: (type)value \
	{ \
		if (self = [super init]) { \
			XPC_THIS_DECL(name); \
			this->value = value; \
		} \
		return self; \
	} \
	- (NSUInteger)hash \
	{ \
		XPC_THIS_DECL(name); \
		return xpc_raw_data_hash(&this->value, sizeof(this->value)); \
	} \
	@end

#define XPC_WRAPPER_CLASS_SERIAL_IMPL(name, type, serial_type, serial_U32_or_U64, serial_uint32_t_or_uint64_t) \
	@implementation XPC_CLASS(name) (XPCSerialization) \
	- (BOOL)serializable \
	{ \
		return YES; \
	} \
	- (NSUInteger)serializationLength \
	{ \
		return xpc_serial_padded_length(sizeof(xpc_serial_type_t)) + xpc_serial_padded_length(sizeof(serial_uint32_t_or_uint64_t)); \
	} \
	+ (instancetype)deserialize: (XPC_CLASS(deserializer)*)deserializer \
	{ \
		XPC_CLASS(name)* result = nil; \
		xpc_serial_type_t inputType = XPC_SERIAL_TYPE_INVALID; \
		serial_uint32_t_or_uint64_t value = 0; \
		if (![deserializer readU32: &inputType]) { \
			goto error_out; \
		} \
		if (inputType != XPC_SERIAL_TYPE_ ## serial_type) { \
			goto error_out; \
		} \
		if (![deserializer read ## serial_U32_or_U64: &value]) { \
			goto error_out; \
		} \
		result = [[[self class] alloc] initWithValue: (type)value]; \
		return result; \
	error_out: \
		if (result != nil) { \
			[result release]; \
		} \
		return nil; \
	} \
	- (BOOL)serialize: (XPC_CLASS(serializer)*)serializer \
	{ \
		XPC_THIS_DECL(name); \
		if (![serializer writeU32: XPC_SERIAL_TYPE_ ## serial_type]) { \
			goto error_out; \
		} \
		if (![serializer write ## serial_U32_or_U64: (serial_uint32_t_or_uint64_t)this->value]) { \
			goto error_out; \
		} \
		return YES; \
	error_out: \
		return NO; \
	} \
	@end

// hack to create symbol aliases programmatically, because the `alias` attribute isn't supported on Darwin platforms
#if defined(__arm64__) || defined(__aarch64__)
#define _CREATE_ALIAS(original, alias) __asm__(".globl " alias "\n.set " alias ", " original)
#else
#define _CREATE_ALIAS(original, alias) __asm__(".globl " original "; .globl " alias "; .equiv " alias ", " original)
#endif

#define XPC_CLASS_SYMBOL(name) _xpc_type_ ## name
#define XPC_CLASS_SYMBOL_DECL(name) \
	XPC_EXPORT struct objc_class XPC_CLASS_SYMBOL(name); \
	_CREATE_ALIAS(OS_OBJC_CLASS_RAW_SYMBOL_NAME(XPC_CLASS(name)), "_" OS_STRINGIFY(XPC_CLASS_SYMBOL(name)))

#define XPC_OBJC_CLASS(name) ((Class)&XPC_CLASS_SYMBOL(name))

#define XPC_GLOBAL_OBJECT_HEADER(className) \
	.os_obj_isa = (const struct xpc_object_vtable_s*)XPC_OBJC_CLASS(className), \
	.os_obj_ref_cnt = _OS_OBJECT_GLOBAL_REFCNT, \
	.os_obj_xref_cnt = _OS_OBJECT_GLOBAL_REFCNT

//
// base XPC class
//

struct xpc_object_vtable_s {
	_OS_OBJECT_CLASS_HEADER();
};

struct xpc_object_s {
	_OS_OBJECT_HEADER(
		const struct xpc_object_vtable_s* os_obj_isa,
		os_obj_ref_cnt,
		os_obj_xref_cnt
	);
};

XPC_EXPORT
@interface XPC_CLASS(object) : OS_OBJECT_CLASS(object) <XPC_CLASS(object)>

@property(readonly, class) NSUInteger instanceSize;

// note that this method returns a string that must be freed
- (char*)xpcDescription;

@end

@class XPC_CLASS(serializer);
@class XPC_CLASS(deserializer);

@interface XPC_CLASS(object) (XPCSerialization)

@property(readonly) BOOL serializable;

// NOTE for implementations: this length MUST include any padding that might be added.
// use `xpc_serial_padded_length` for each component of the serialization.
@property(readonly) NSUInteger serializationLength;

+ (instancetype)deserialize: (XPC_CLASS(deserializer)*)deserializer;

- (BOOL)serialize: (XPC_CLASS(serializer)*)serializer;

@end

#endif // _XPC_OBJECTS_BASE_H_
