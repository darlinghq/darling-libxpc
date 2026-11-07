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

#import <xpc/objects/bool.h>
#import <xpc/util.h>
#import <xpc/xpc.h>
#import <xpc/serialization.h>

#undef bool

// workaround because `xpc/xpc.h` uses `_xpc_bool_s` instead of `xpc_bool_s`
struct _xpc_bool_s {
	struct xpc_bool_s the_real_thing;
};

XPC_CLASS_SYMBOL_DECL(bool);

XPC_EXPORT
const struct _xpc_bool_s _xpc_bool_true = {
	.the_real_thing = {
		.base = {
			XPC_GLOBAL_OBJECT_HEADER(bool),
		},
		.value = true,
	},
};
XPC_GLOBAL_OBJECT_REGISTER(_xpc_bool_true);

XPC_EXPORT
const struct _xpc_bool_s _xpc_bool_false = {
	.the_real_thing = {
		.base = {
			XPC_GLOBAL_OBJECT_HEADER(bool),
		},
		.value = false,
	},
};
XPC_GLOBAL_OBJECT_REGISTER(_xpc_bool_false);

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(bool)

XPC_CLASS_HEADER(bool);

- (char*)xpcDescription
{
	char* output = NULL;
	asprintf(&output, "<%s: %s>", xpc_class_name(self), self.value ? "TRUE" : "FALSE");
	return output;
}

- (BOOL)value
{
	XPC_THIS_DECL(bool);
	return this->value;
}

- (void)setValue: (BOOL)value
{
	XPC_THIS_DECL(bool);
	this->value = value;
}

- (instancetype)initWithValue: (BOOL)value
{
	if (self = [super init]) {
		XPC_THIS_DECL(bool);
		this->value = value;
	}
	return self;
}


+ (instancetype)boolForValue: (BOOL)value
{
	if (value) {
		return XPC_CAST(bool, &_xpc_bool_true);
	} else {
		return XPC_CAST(bool, &_xpc_bool_false);
	}
}

- (NSUInteger)hash
{
	XPC_THIS_DECL(bool);

	if (this->value) {
		return 0xb001;
	} else {
		return 0x100b;
	}
}

@end

@implementation XPC_CLASS(bool) (XPCSerialization)

- (BOOL)serializable
{
	return YES;
}

- (NSUInteger)serializationLength
{
	return xpc_serial_padded_length(sizeof(xpc_serial_type_t)) + xpc_serial_padded_length(sizeof(uint32_t));
}

+ (instancetype)deserialize: (XPC_CLASS(deserializer)*)deserializer
{
	XPC_CLASS(bool)* result = nil;
	xpc_serial_type_t type = XPC_SERIAL_TYPE_INVALID;
	uint32_t value = 0;

	if (![deserializer readU32: &type]) {
		goto error_out;
	}
	if (type != XPC_SERIAL_TYPE_BOOL) {
		goto error_out;
	}

	if (![deserializer readU32: &value]) {
		goto error_out;
	}

	result = [[self class] boolForValue: !!value];

	return result;

error_out:
	if (result != nil) {
		[result release];
	}
	return nil;
}

- (BOOL)serialize: (XPC_CLASS(serializer)*)serializer
{
	XPC_THIS_DECL(bool);

	if (![serializer writeU32: XPC_SERIAL_TYPE_BOOL]) {
		goto error_out;
	}

	if (![serializer writeU32: this->value]) {
		goto error_out;
	}

	return YES;

error_out:
	return NO;
}

@end

#define bool _Bool

//
// C API
//

XPC_EXPORT
xpc_object_t xpc_bool_create(bool value) {
	return [XPC_CLASS(bool) boolForValue: value];
};

XPC_EXPORT
bool xpc_bool_get_value(xpc_object_t xbool) {
#undef bool
	TO_OBJC_CHECKED(bool, xbool, boolObj) {
#define bool _Bool
		return boolObj.value;
	}
	return false;
};

//
// private C API
//

XPC_EXPORT
xpc_object_t _xpc_bool_create_distinct(bool value) {
	return [[XPC_CLASS(bool) alloc] initWithValue: value];
};

XPC_EXPORT
void _xpc_bool_set_value(xpc_object_t xbool, bool value) {
#undef bool
	TO_OBJC_CHECKED(bool, xbool, boolObj) {
#define bool _Bool
		boolObj.value = value;
	}
};
