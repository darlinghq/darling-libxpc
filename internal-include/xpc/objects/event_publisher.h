/**
 * This file is part of Darling.
 *
 * Copyright (C) 2026 Darling Developers
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

#ifndef _XPC_OBJECTS_EVENT_PUBLISHER_H_
#define _XPC_OBJECTS_EVENT_PUBLISHER_H_

#import <xpc/objects/base.h>
#import <xpc/launchd_defs.h>
#import <dispatch/dispatch.h>

XPC_CLASS_DECL(event_publisher);

typedef void (^xpc_event_publisher_handler_t)(xpc_event_publisher_action_t action, uint64_t event_token, xpc_object_t descriptor);
typedef void (^xpc_event_publisher_error_handler_t)(int error);

struct xpc_event_publisher_s {
	struct xpc_object_s base;
	char* name;
	dispatch_queue_t queue;
	xpc_event_publisher_handler_t handler;
	xpc_event_publisher_error_handler_t error_handler;
	bool activated;
};

@interface XPC_CLASS_INTERFACE(event_publisher)

- (instancetype)initWithName: (const char*)name queue: (dispatch_queue_t)queue;

@end

#endif // _XPC_OBJECTS_EVENT_PUBLISHER_H_
