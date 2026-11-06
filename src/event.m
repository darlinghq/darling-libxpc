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

#import <xpc/objects/event_publisher.h>
#import <xpc/xpc.h>
#import <xpc/util.h>
#import <Block.h>
#include <stdlib.h>
#include <string.h>

// An event publisher is how a daemon learns about the launchd event stream
// subscriptions of its clients. Darling's launchd has no event streams, so
// there is never anything to add or remove, but a publisher still has to go
// through the lifecycle its owner expects: once activated, the handler is
// told on the publisher's queue that the initial set of subscriptions has
// been delivered (XPC_EVENT_PUBLISHER_ACTION_INITIAL_BARRIER). Daemons such
// as notifyd only start serving after that.

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(event_publisher)

XPC_CLASS_HEADER(event_publisher);

- (void)dealloc
{
	XPC_THIS_DECL(event_publisher);
	if (this->handler) {
		Block_release(this->handler);
	}
	if (this->error_handler) {
		Block_release(this->error_handler);
	}
	if (this->queue) {
		dispatch_release(this->queue);
	}
	free(this->name);
	[super dealloc];
}

- (char*)xpcDescription
{
	XPC_THIS_DECL(event_publisher);
	char* output = NULL;
	asprintf(&output, "<%s: %s>", xpc_class_name(self), this->name ? this->name : "");
	return output;
}

- (instancetype)initWithName: (const char*)name queue: (dispatch_queue_t)queue
{
	if (self = [super init]) {
		XPC_THIS_DECL(event_publisher);
		this->name = name ? strdup(name) : NULL;
		if (!queue) {
			queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
		}
		dispatch_retain(queue);
		this->queue = queue;
	}
	return self;
}

@end

XPC_EXPORT const char* const _xpc_event_key_name = "XPCEventName";
XPC_EXPORT const char* const _xpc_event_key_stream_name = "XPCEventStreamName";

//
// private C API
//

XPC_EXPORT
void xpc_event_publisher_activate(xpc_event_publisher_t xpub) {
	TO_OBJC_CHECKED(event_publisher, xpub, publisher) {
		struct xpc_event_publisher_s* this = (struct xpc_event_publisher_s*)publisher;
		if (this->activated) {
			return;
		}
		this->activated = true;

		if (!this->handler) {
			return;
		}

		// There are no subscriptions to deliver first, so the barrier comes
		// right away, but asynchronously on the publisher's queue, after
		// activation has returned.
		xpc_event_publisher_handler_t handler = Block_copy(this->handler);
		dispatch_async(this->queue, ^{
			handler(XPC_EVENT_PUBLISHER_ACTION_INITIAL_BARRIER, 0, NULL);
			Block_release(handler);
		});
	}
};

XPC_EXPORT
xpc_object_t xpc_event_publisher_create(const char* name, void* some_parameter) {
	// The second parameter is the queue the handlers run on
	return [[XPC_CLASS(event_publisher) alloc] initWithName: name queue: (dispatch_queue_t)some_parameter];
};

XPC_EXPORT
int xpc_event_publisher_fire(xpc_event_publisher_t xpub, uint64_t token, xpc_object_t details) {
	xpc_stub();
	return -1;
};

XPC_EXPORT
int xpc_event_publisher_fire_noboost(xpc_event_publisher_t xpub, uint64_t token, xpc_object_t details) {
	xpc_stub();
	return -1;
};

XPC_EXPORT
int xpc_event_publisher_fire_with_reply() {
	// i didn't feel like determining the parameters for this one
	// should be similar to `xpc_event_publisher_fire`
	xpc_stub();
	return -1;
};

XPC_EXPORT
xpc_object_t xpc_event_publisher_fire_with_reply_sync() {
	// should be similar to `xpc_event_publisher_fire_with_reply`
	xpc_stub();
	return NULL;
};

XPC_EXPORT
au_asid_t xpc_event_publisher_get_subscriber_asid(xpc_event_publisher_t xpub, uint64_t token) {
	xpc_stub();
	return -1;
};

XPC_EXPORT
void xpc_event_publisher_set_error_handler(xpc_event_publisher_t xpub, void (^handler)()) {
	// The handler takes an error code. Without event streams, nothing
	// reports an error to it.
	TO_OBJC_CHECKED(event_publisher, xpub, publisher) {
		struct xpc_event_publisher_s* this = (struct xpc_event_publisher_s*)publisher;
		xpc_event_publisher_error_handler_t old = this->error_handler;
		this->error_handler = handler ? Block_copy((xpc_event_publisher_error_handler_t)handler) : NULL;
		if (old) {
			Block_release(old);
		}
	}
};

XPC_EXPORT
void xpc_event_publisher_set_handler(xpc_event_publisher_t xpub, void (^handler)()) {
	// The handler takes an xpc_event_publisher_action_t, the event token and
	// the subscription's descriptor.
	TO_OBJC_CHECKED(event_publisher, xpub, publisher) {
		struct xpc_event_publisher_s* this = (struct xpc_event_publisher_s*)publisher;
		xpc_event_publisher_handler_t old = this->handler;
		this->handler = handler ? Block_copy((xpc_event_publisher_handler_t)handler) : NULL;
		if (old) {
			Block_release(old);
		}
	}
};

XPC_EXPORT
void xpc_event_publisher_set_initial_load_completed_handler_4remoted(xpc_event_publisher_t xpub, void (^handler)()) {
	// once again, no clue about the handler parameters
	xpc_stub();
};

XPC_EXPORT
int xpc_event_publisher_set_subscriber_keepalive(xpc_event_publisher_t xpub, uint64_t token, bool state) {
	xpc_stub();
	return -1;
};

XPC_EXPORT
int xpc_event_stream_check_in() {
	// not a stub
	// just returns 0
	return 0;
};

XPC_EXPORT
int xpc_event_stream_check_in2() {
	// not a stub
	// just returns 0
	return 0;
};

XPC_EXPORT
int xpc_get_event_name(const char* stream, uint64_t token, char* out_name) {
	xpc_stub();
	return -1;
};

XPC_EXPORT
xpc_object_t xpc_copy_event(const char* stream, const char* name) {
	// returns a dictionary
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_copy_event_entitlements(const char* stream, uint64_t token) {
	// returns a dictionary
	xpc_stub();
	return NULL;
};

XPC_EXPORT
void xpc_set_event(const char* stream, const char* name, xpc_object_t descriptor) {
	xpc_stub();
};

XPC_EXPORT
void xpc_set_event_state(const char* stream, uint64_t token, bool state) {
	xpc_stub();
};

XPC_EXPORT
void xpc_set_event_stream_handler(const char* connection_name, dispatch_queue_t queue, void (^handler)(xpc_object_t event)) {
	xpc_stub();
};

XPC_EXPORT
void xpc_set_event_with_flags(const char* stream, const char* name, xpc_object_t descriptor, uint64_t flags) {
	xpc_stub();
};
