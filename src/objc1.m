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

// The i386 type symbols and the mapping between them and libxpc's classes
// (see xpc/objc1.h).

#import <xpc/objects/base.h>
#import <xpc/xpc.h>
#import <xpc/objc1.h>
#import <objc/runtime.h>

// `bool` is a macro; the type list below needs the plain word.
#undef bool

#if XPC_OBJC1

// This file must not implement any class: here the class name symbols are
// undefined, so the references below are resolved by the linker to the
// class structures. (In the file that implements a class, its name symbol
// is the absolute value 0.)
#define XPC_OBJC1_CLASS_REF(sym, cls) \
	extern struct objc_class _xpc_objc1_class_ ## sym __asm__(".objc_class_name_OS_xpc_" #cls)

// The type symbol: a distinct constant object named after the class.
#define XPC_OBJC1_TYPE_DEF(sym, cls) \
	XPC_EXPORT const struct objc_class _xpc_type_ ## sym = { .name = "OS_xpc_" #cls }

#define XPC_OBJC1_TYPES(_) \
	_(base, object) \
	_(activity, activity) \
	_(array, array) \
	_(bool, bool) \
	_(bundle, bundle) \
	_(connection, connection) \
	_(data, data) \
	_(date, date) \
	_(deserializer, deserializer) \
	_(dictionary, dictionary) \
	_(double, double) \
	_(endpoint, endpoint) \
	_(error, error) \
	_(fd, fd) \
	_(file_transfer, file_transfer) \
	_(int64, int64) \
	_(mach_recv, mach_recv) \
	_(mach_send, mach_send) \
	_(null, null) \
	_(pipe, pipe) \
	_(pointer, pointer) \
	_(serializer, serializer) \
	_(service, service) \
	_(service_instance, service_instance) \
	_(shmem, shmem) \
	_(string, string) \
	_(uint64, uint64) \
	_(uuid, uuid)

#define XPC_OBJC1_DECLARE(sym, cls) XPC_OBJC1_CLASS_REF(sym, cls); XPC_OBJC1_TYPE_DEF(sym, cls);
XPC_OBJC1_TYPES(XPC_OBJC1_DECLARE)

static const struct {
	const struct objc_class* type;
	Class cls;
} xpc_objc1_types[] = {
#define XPC_OBJC1_ENTRY(sym, cls) { &_xpc_type_ ## sym, (Class)&_xpc_objc1_class_ ## sym },
	XPC_OBJC1_TYPES(XPC_OBJC1_ENTRY)
};

Class xpc_objc1_class_for_type(const void* type) {
	for (size_t i = 0; i < sizeof(xpc_objc1_types) / sizeof(*xpc_objc1_types); ++i) {
		if (xpc_objc1_types[i].type == type) {
			return xpc_objc1_types[i].cls;
		}
	}
	return NULL;
};

const void* xpc_objc1_type_for_class(Class cls) {
	for (size_t i = 0; i < sizeof(xpc_objc1_types) / sizeof(*xpc_objc1_types); ++i) {
		if (xpc_objc1_types[i].cls == cls) {
			return xpc_objc1_types[i].type;
		}
	}
	return cls;
};

// Pointers to every object registered with XPC_GLOBAL_OBJECT_REGISTER.
extern const void* const xpc_objc1_globals_start __asm__("section$start$__DATA$__xpc_globals");
extern const void* const xpc_objc1_globals_end __asm__("section$end$__DATA$__xpc_globals");

void xpc_objc1_fix_global_objects(void) {
	for (const void* const* ref = &xpc_objc1_globals_start; ref < &xpc_objc1_globals_end; ++ref) {
		// The objects are defined const, but they live in a writable data
		// section (they hold relocated pointers) and this runs once, at
		// library initialization, before anyone can use them.
		struct xpc_object_s* object = (struct xpc_object_s*)*ref;
		Class cls = xpc_objc1_class_for_type(object->os_obj_isa);
		if (cls != NULL) {
			object->os_obj_isa = (const struct xpc_object_vtable_s*)cls;
		}
	}
};

#endif
