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

#import <xpc/objects/null.h>
#import <xpc/util.h>
#import <xpc/xpc.h>
#import <xpc/serialization.h>

XPC_CLASS_SYMBOL_DECL(null);

struct xpc_null_s _xpc_null = {
	.base = {
		XPC_GLOBAL_OBJECT_HEADER(null),
	},
};
XPC_GLOBAL_OBJECT_REGISTER(_xpc_null);

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(null)

XPC_CLASS_HEADER(null);

- (char*)xpcDescription
{
	char* output = NULL;
	asprintf(&output, "<%s>", xpc_class_name(self));
	return output;
}

+ (instancetype)null
{
	return XPC_CAST(null, &_xpc_null);
}

- (NSUInteger)hash
{
#if __LP64__
	return 0x804201026298ULL;
#else
	return 0x8042010U;
#endif
}

@end

@implementation XPC_CLASS(null) (XPCSerialization)

- (BOOL)serializable
{
	return YES;
}

- (NSUInteger)serializationLength
{
	return xpc_serial_padded_length(sizeof(xpc_serial_type_t));
}

+ (instancetype)deserialize: (XPC_CLASS(deserializer)*)deserializer
{
	xpc_serial_type_t type = XPC_SERIAL_TYPE_INVALID;

	if (![deserializer readU32: &type]) {
		goto error_out;
	}
	if (type != XPC_SERIAL_TYPE_NULL) {
		goto error_out;
	}

	return [[self class] null];

error_out:
	return nil;
}

- (BOOL)serialize: (XPC_CLASS(serializer)*)serializer
{
	return [serializer writeU32: XPC_SERIAL_TYPE_NULL];
}

@end

//
// C API
//

XPC_EXPORT
xpc_object_t xpc_null_create(void) {
	return [XPC_CLASS(null) null];
};
