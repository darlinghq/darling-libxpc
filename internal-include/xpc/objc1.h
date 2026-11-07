/**
 * This file is part of Darling.
 *
 * Copyright (C) 2026 Lubos Dolezel
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

#ifndef _XPC_OBJC1_H_
#define _XPC_OBJC1_H_

// i386 uses the legacy Objective-C ABI (objc1). There, a class cannot be
// given a second, exported name: the class name symbol (.objc_class_name_*)
// is only assigned by the linker, and the linker ignores other labels on a
// class. So on i386 the exported type symbols (`_xpc_type_*`, i.e.
// `XPC_TYPE_*`) are separate constant objects, and libxpc maps between them
// and its classes; elsewhere the type symbol is the class itself and the
// mapping is the identity.
//
// Everything specific to i386 is here and in `objc1.m`.

#include <objc/objc.h>

#ifdef __cplusplus
extern "C" {
#endif

#if XPC_OBJC1

// Maps a type symbol to the class that implements it, or NULL.
Class xpc_objc1_class_for_type(const void* type);

// Maps a class to its type symbol, or returns the class if it has none.
const void* xpc_objc1_type_for_class(Class cls);

// Gives the statically allocated objects (`xpc_bool_true`, the error
// dictionaries, ...) their classes. Their isa initially holds their type
// symbol, the only constant available for it. Called at library
// initialization.
void xpc_objc1_fix_global_objects(void);

#define XPC_CLASS_FOR_TYPE(type) xpc_objc1_class_for_type(type)
#define XPC_TYPE_FOR_CLASS(cls) ((xpc_type_t)xpc_objc1_type_for_class(cls))

// Records a statically allocated object for `xpc_objc1_fix_global_objects`.
#define XPC_GLOBAL_OBJECT_REGISTER(object) \
	static const void* const _xpc_global_object_ref_ ## object \
		__attribute__((used, section("__DATA,__xpc_globals"))) = &object

#else

#define XPC_CLASS_FOR_TYPE(type) ((Class)(type))
#define XPC_TYPE_FOR_CLASS(cls) ((xpc_type_t)(cls))
#define XPC_GLOBAL_OBJECT_REGISTER(object)

#endif

#ifdef __cplusplus
};
#endif

#endif // _XPC_OBJC1_H_
