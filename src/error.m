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

#import <xpc/objects/error.h>
#import <xpc/objects/string.h>
#import <xpc/xpc.h>
#import <xpc/util.h>

XPC_CLASS_SYMBOL_DECL(error);

#define XPCErrorDescriptionKey "XPCErrorDescription"
const char* const _xpc_error_key_description = XPCErrorDescriptionKey;

// workaround like in `bool.m`
struct _xpc_dictionary_s {
	struct xpc_error_s the_real_thing;
};

#define XPC_ERROR_DEFINITION(_name, _description) \
	struct xpc_string_s _xpc_error_ ## _name ## _entry_string = { \
		.base = { \
			XPC_GLOBAL_OBJECT_HEADER(string), \
		}, \
		.byteLength = NSUIntegerMax, \
		.string = _description, \
		.freeWhenDone = false \
	}; \
	XPC_GLOBAL_OBJECT_REGISTER(_xpc_error_ ## _name ## _entry_string); \
	extern const struct _xpc_dictionary_s _xpc_error_ ## _name; \
	struct xpc_dictionary_entry_s _xpc_error_ ## _name ## _entry = { \
		.link = { \
			.le_next = NULL, \
			.le_prev = (struct xpc_dictionary_entry_s**)&LIST_FIRST(&_xpc_error_ ## _name.the_real_thing.base.head), \
		}, \
		.object = XPC_CAST(string, &_xpc_error_ ## _name ## _entry_string), \
		.name = XPCErrorDescriptionKey, \
	}; \
	XPC_EXPORT const struct _xpc_dictionary_s _xpc_error_ ## _name = { \
		.the_real_thing = { \
			.base = { \
				.base = { \
					XPC_GLOBAL_OBJECT_HEADER(error), \
				}, \
				.size = 1, \
				.head = { \
					.lh_first = &_xpc_error_ ## _name ## _entry, \
				}, \
			}, \
		}, \
	}; \
	XPC_GLOBAL_OBJECT_REGISTER(_xpc_error_ ## _name);

XPC_ERROR_DEFINITION(connection_interrupted, "Connection interrupted");
XPC_ERROR_DEFINITION(connection_invalid, "Connection invalid");
XPC_ERROR_DEFINITION(termination_imminent, "Termination imminent");

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(error)

XPC_CLASS_HEADER(error);

- (char*)xpcDescription
{
	char* output = NULL;
	asprintf(&output, "<%s: %s>", xpc_class_name(self), [self stringForKey: XPCErrorDescriptionKey].CString);
	return output;
}

@end

//
// C API
//

XPC_EXPORT
const char* xpc_strerror(int error) {
	return NULL;
};
