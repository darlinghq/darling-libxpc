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

#import <os/object.h>

#if __OBJC2__
// Objective-C 2.0 marks `struct objc_class` as unavailable by default.
// we know what we're doing; let's prevent the compiler from complaining.
#undef OBJC2_UNAVAILABLE
#define OBJC2_UNAVAILABLE
#endif

// i386 uses the legacy Objective-C ABI: see xpc/objc1.h.
#if defined(__i386__)
#define XPC_OBJC1 1
#else
#define XPC_OBJC1 0
#endif

#if XPC_OBJC1
#define XPC_TYPE(name) const struct objc_class name
#else
#define XPC_TYPE(name) struct objc_class name
#endif
#define XPC_DECL(name) OS_OBJECT_DECL_SUBCLASS(name, xpc_object)
