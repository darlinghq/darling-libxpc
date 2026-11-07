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
#include <xpc/objc1.h>

void xpc_stub_init(void);

extern void bootstrap_init(void); // in liblaunch

XPC_EXPORT
void _libxpc_initializer(void)
{
#if XPC_OBJC1
	xpc_objc1_fix_global_objects();
#endif
	xpc_stub_init();
	bootstrap_init();
}

XPC_EXPORT
void xpc_atfork_child(void)
{
	bootstrap_init();
}

XPC_EXPORT
void xpc_atfork_parent(void)
{
}

XPC_EXPORT
void xpc_atfork_prepare(void)
{
}


