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

#import <xpc/objects/pointer.h>
#import <xpc/util.h>
#import <xpc/xpc.h>
#import <xpc/serialization.h>

XPC_WRAPPER_CLASS_IMPL(pointer, void*, "%p");
XPC_WRAPPER_CLASS_SERIAL_IMPL(pointer, void*, POINTER, U64, uint64_t);

//
// C API
//

XPC_EXPORT
xpc_object_t xpc_pointer_create(void* value) {
	return [[XPC_CLASS(pointer) alloc] initWithValue: value];
};

XPC_EXPORT
void* xpc_pointer_get_value(xpc_object_t xptr) {
	TO_OBJC_CHECKED(pointer, xptr, ptr) {
		return ptr.value;
	}
	return NULL;
};
