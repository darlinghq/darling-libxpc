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
#import <xpc/objects/connection.h>
#import <xpc/objects/dictionary.h>
#import <xpc/objects/mach_recv.h>
#import <xpc/xpc.h>
#import <xpc/private/pipe.h>
#import <xpc/private/mach_recv.h>
#import <xpc/util.h>
#import <Block.h>
#include <servers/bootstrap.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

XPC_LOGGER_DEF(event);

// An event publisher is how a daemon learns about the launchd event stream
// subscriptions of its clients. Darling's launchd has no publishers (its
// streams are served by the one job marked EventMonitor, through the provider
// routines below), so there is never anything to add or remove, but a
// publisher still has to go
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

//
// launchd event routines
//
// A job's LaunchEvents are kept by launchd per stream. The calls below are
// the client side of launchd's XPC event routines (`xpc_event_t` in
// <xpc/launchd_defs.h>): each one is a pipe routine to launchd over the
// bootstrap port, and launchd reports a failure in the reply under
// XPC_EVENT_ROUTINE_KEY_ERROR.
//

static int xpc_event_routine(xpc_event_t op, xpc_object_t request, xpc_object_t* out_reply) {
	xpc_pipe_t pipe = xpc_pipe_create_from_port(bootstrap_port, 0);
	if (!pipe) {
		return EPIPE;
	}

	xpc_dictionary_set_uint64(request, XPC_EVENT_ROUTINE_KEY_OP, op);

	xpc_object_t reply = NULL;
	int status = xpc_pipe_routine(pipe, request, &reply);
	xpc_release(pipe);

	if (status == 0) {
		status = (int)xpc_dictionary_get_uint64(reply, XPC_EVENT_ROUTINE_KEY_ERROR);
		if (status == 0 && out_reply) {
			*out_reply = reply;
			reply = NULL;
		}
	}

	if (reply) {
		xpc_release(reply);
	}
	return status;
};

static xpc_object_t xpc_event_request_create(const char* stream) {
	xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
	if (stream) {
		xpc_dictionary_set_string(request, XPC_EVENT_ROUTINE_KEY_STREAM, stream);
	}
	return request;
};

// Returns a retained copy of the reply's value for `key`, or NULL.
static xpc_object_t xpc_event_routine_copy_value(xpc_event_t op, xpc_object_t request, const char* key) {
	xpc_object_t reply = NULL;
	xpc_object_t value = NULL;

	if (xpc_event_routine(op, request, &reply) == 0) {
		value = xpc_dictionary_get_value(reply, key);
		if (value) {
			xpc_retain(value);
		}
		xpc_release(reply);
	}

	return value;
};

XPC_EXPORT
int xpc_get_event_name(const char* stream, uint64_t token, char* out_name) {
	// `out_name` is an `event_name_t`.
	if (!stream || !out_name) {
		return EINVAL;
	}

	xpc_object_t request = xpc_event_request_create(stream);
	xpc_dictionary_set_uint64(request, XPC_EVENT_ROUTINE_KEY_TOKEN, token);

	xpc_object_t reply = NULL;
	int status = xpc_event_routine(XPC_EVENT_GET_NAME, request, &reply);
	xpc_release(request);

	if (status == 0) {
		const char* name = xpc_dictionary_get_string(reply, XPC_EVENT_ROUTINE_KEY_NAME);
		if (name) {
			strlcpy(out_name, name, sizeof(event_name_t));
		} else {
			status = EINVAL;
		}
		xpc_release(reply);
	}

	return status;
};

XPC_EXPORT
xpc_object_t xpc_copy_event(const char* stream, const char* name) {
	// launchd returns the descriptor of the named event, or with a NULL
	// name, a dictionary of all the stream's events by name, or with a NULL
	// stream too, a dictionary of streams.
	xpc_object_t request = xpc_event_request_create(stream);
	if (name) {
		xpc_dictionary_set_string(request, XPC_EVENT_ROUTINE_KEY_NAME, name);
	}

	xpc_object_t event = xpc_event_routine_copy_value(XPC_EVENT_COPY, request, XPC_EVENT_ROUTINE_KEY_EVENT);
	xpc_release(request);
	return event;
};

XPC_EXPORT
xpc_object_t xpc_copy_event_entitlements(const char* stream, uint64_t token) {
	if (!stream) {
		return NULL;
	}

	xpc_object_t request = xpc_event_request_create(stream);
	xpc_dictionary_set_uint64(request, XPC_EVENT_ROUTINE_KEY_TOKEN, token);

	xpc_object_t entitlements = xpc_event_routine_copy_value(XPC_EVENT_COPY_ENTITLEMENTS, request, XPC_EVENT_ROUTINE_KEY_ENTITLEMENTS);
	xpc_release(request);
	return entitlements;
};

XPC_EXPORT
void xpc_set_event_with_flags(const char* stream, const char* name, xpc_object_t descriptor, uint64_t flags) {
	// A NULL descriptor removes the event.
	if (!stream || !name) {
		return;
	}

	xpc_object_t request = xpc_event_request_create(stream);
	xpc_dictionary_set_string(request, XPC_EVENT_ROUTINE_KEY_NAME, name);
	if (descriptor) {
		xpc_dictionary_set_value(request, XPC_EVENT_ROUTINE_KEY_EVENT, descriptor);
	}
	xpc_dictionary_set_uint64(request, XPC_EVENT_ROUTINE_KEY_FLAGS, flags);

	int status = xpc_event_routine(XPC_EVENT_SET, request, NULL);
	xpc_release(request);

	if (status != 0) {
		xpc_log_error(event, "setting event %s/%s failed: %d", stream, name, status);
	}
};

XPC_EXPORT
void xpc_set_event(const char* stream, const char* name, xpc_object_t descriptor) {
	xpc_set_event_with_flags(stream, name, descriptor, 0);
};

XPC_EXPORT
void xpc_set_event_state(const char* stream, uint64_t token, bool state) {
	// Only the event monitor job may set states.
	if (!stream) {
		return;
	}

	xpc_object_t request = xpc_event_request_create(stream);
	xpc_dictionary_set_uint64(request, XPC_EVENT_ROUTINE_KEY_TOKEN, token);
	xpc_dictionary_set_bool(request, XPC_EVENT_ROUTINE_KEY_STATE, state);

	int status = xpc_event_routine(XPC_EVENT_PROVIDER_SET_STATE, request, NULL);
	xpc_release(request);

	if (status != 0) {
		xpc_log_error(event, "setting the state of event %s/%llu failed: %d", stream, token, status);
	}
};

XPC_EXPORT
void xpc_set_event_stream_handler(const char* stream, dispatch_queue_t targetq, xpc_handler_t handler) {
	// The job checks in with launchd for the stream and gets the receive
	// right of its event channel for the stream. An event provider looks the
	// channel up and sends each event to it as a dictionary, over a pipe or
	// a connection. launchd starts the job on demand when an event arrives
	// while the job is not running.
	if (!stream || !handler) {
		return;
	}

	xpc_object_t request = xpc_event_request_create(stream);
	xpc_object_t reply = NULL;
	int status = xpc_event_routine(XPC_EVENT_CHECK_IN, request, &reply);
	xpc_release(request);

	if (status != 0) {
		xpc_log_error(event, "checking in for event stream %s failed: %d", stream, status);
		return;
	}

	mach_port_t port = MACH_PORT_NULL;
	xpc_object_t xport = xpc_dictionary_get_value(reply, XPC_EVENT_ROUTINE_KEY_PORT);
	if (XPC_CHECK(mach_recv, xport)) {
		port = xpc_mach_recv_extract_right(xport);
	}
	xpc_release(reply);

	if (!MACH_PORT_VALID(port)) {
		xpc_log_error(event, "launchd returned no channel for event stream %s", stream);
		return;
	}

	// Events are delivered one at a time, in order, on the target queue
	// (the default target queue if it is NULL).
	dispatch_queue_t queue = dispatch_queue_create("com.apple.xpc.event-stream", DISPATCH_QUEUE_SERIAL);
	dispatch_set_target_queue(queue, targetq);

	XPC_CLASS(connection)* listener = [[XPC_CLASS(connection) alloc] initAsListenerWithReceivePort: port queue: queue];
	if (!listener) {
		xpc_log_error(event, "cannot listen on the channel for event stream %s", stream);
		dispatch_release(queue);
		return;
	}

	xpc_handler_t event_handler = Block_copy(handler);
	xpc_connection_set_event_handler(listener, ^(xpc_object_t object) {
		if (!XPC_CHECK(connection, object)) {
			return;
		}
		xpc_connection_t peer = (xpc_connection_t)object;
		xpc_connection_set_target_queue(peer, queue);
		xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
			// Errors only say that the provider closed its end.
			if (XPC_CHECK(dictionary, event)) {
				event_handler(event);
			}
		});
		xpc_connection_resume(peer);
	});

	// The listener and its queue stay for the life of the process.
	xpc_connection_resume(listener);
};
