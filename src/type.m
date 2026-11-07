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

#import <xpc/xpc.h>
#import <xpc/util.h>
#import <objc/runtime.h>

//
// C API
//

XPC_EXPORT
xpc_type_t xpc_get_type(xpc_object_t xobject) {
	TO_OBJC_CHECKED(object, xobject, object) {
		return XPC_TYPE_FOR_CLASS([object class]);
	}
	return NULL;
};



//
// private C API
//

XPC_EXPORT
const char* xpc_type_get_name(xpc_type_t xtype) {
	return class_getName(XPC_CLASS_FOR_TYPE(xtype));
};

XPC_EXPORT
Class xpc_get_class4NSXPC(xpc_type_t xtype) {
	return XPC_CLASS_FOR_TYPE(xtype);
};
XPC_EXPORT
bool xpc_is_kind_of_xpc_object4NSXPC(xpc_object_t object) {
	return [object isKindOfClass: [XPC_CLASS(object) class]];
};

struct some_extension_type_struct;

XPC_EXPORT
void xpc_extension_type_init(struct some_extension_type_struct* extension_type, void* some_user_function_probably) {
	xpc_stub();
};
