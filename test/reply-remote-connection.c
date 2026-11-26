// Plain-guest test: which connection xpc_dictionary_get_remote_connection reports for a reply.
// Needs the launchd test service (launchd-service/, plist installed with the tests) to be registered; the service
// answers a "hello" message with a "hello" reply.
//   Documented (xpc_dictionary_get_remote_connection): "any other dictionary" than one received by an event handler
//   or created by xpc_dictionary_create_reply gets NULL.
//   Not documented, observed on macOS 26.7.3: a reply handed to a reply handler, or returned by
//   xpc_connection_send_message_with_reply_sync, reports the connection it arrived on, like a message handed to the
//   event handler. The weak-reference cases pin our choice that the dictionary does not keep the connection alive.
#include <dispatch/dispatch.h>
#include <xpc/xpc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "launchd-service/service.h"

#define FAIL(...) do { fprintf(stderr, "FAIL: " __VA_ARGS__); fputc('\n', stderr); failures++; } while (0)

static int failures;

// xpc_dictionary_get_remote_connection hands out an autoreleased object, and this program has no autorelease pool of
// its own on the main thread: scope one around each use, or every call would leak a reference on the connection.
extern void* objc_autoreleasePoolPush(void);
extern void objc_autoreleasePoolPop(void* pool);

static xpc_connection_t remote_of(xpc_object_t reply) {
	void* pool = objc_autoreleasePoolPush();
	xpc_connection_t remote = xpc_dictionary_get_remote_connection(reply);
	objc_autoreleasePoolPop(pool);
	return remote; // only compared, never used: it may be gone
}

static xpc_connection_t make_connection(dispatch_semaphore_t invalid) {
	dispatch_queue_t q = dispatch_queue_create("reply-remote-connection.target", NULL);
	xpc_connection_t conn = xpc_connection_create_mach_service(TEST_SERVICE_NAME, q, 0);
	xpc_connection_set_event_handler(conn, ^(xpc_object_t event) {
		if (event == XPC_ERROR_CONNECTION_INVALID && invalid) {
			dispatch_semaphore_signal(invalid);
		}
	});
	xpc_connection_resume(conn);
	return conn;
}

static xpc_object_t hello(void) {
	xpc_object_t m = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_uint64(m, MESSAGE_TYPE_KEY, test_service_message_type_hello);
	xpc_dictionary_set_string(m, HELLO_KEY, "hello from the reply-remote-connection test");
	return m;
}

static int is_hello_reply(xpc_object_t reply) {
	return reply && xpc_get_type(reply) == XPC_TYPE_DICTIONARY &&
	       xpc_dictionary_get_uint64(reply, MESSAGE_TYPE_KEY) == test_service_message_type_hello;
}

// the reply must report conn, and conn must still work through the reported object
static void check_reply(const char* label, xpc_connection_t conn, xpc_object_t reply) {
	void* pool = objc_autoreleasePoolPush();
	if (!is_hello_reply(reply)) {
		FAIL("%s: the server did not answer hello with a hello dictionary", label);
		goto out;
	}
	xpc_connection_t remote = xpc_dictionary_get_remote_connection(reply);
	if (remote == NULL) {
		FAIL("%s: xpc_dictionary_get_remote_connection returned NULL for a reply", label);
		goto out;
	}
	if (remote != conn) {
		FAIL("%s: xpc_dictionary_get_remote_connection returned %p, expected the connection %p", label, (void*)remote, (void*)conn);
		goto out;
	}
	if (xpc_connection_get_pid(remote) != xpc_connection_get_pid(conn)) {
		FAIL("%s: the reported connection has pid %d, the original %d", label, (int)xpc_connection_get_pid(remote), (int)xpc_connection_get_pid(conn));
		goto out;
	}
	xpc_object_t again = xpc_connection_send_message_with_reply_sync(remote, hello());
	if (!is_hello_reply(again)) {
		FAIL("%s: a message sent over the reported connection was not answered", label);
	} else {
		printf("PASS: %s\n", label);
	}
	xpc_release(again);
out:
	objc_autoreleasePoolPop(pool);
}

static void run_async(const char* label, dispatch_queue_t replyq) {
	xpc_connection_t conn = make_connection(NULL);
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	__block xpc_object_t reply = NULL;
	xpc_connection_send_message_with_reply(conn, hello(), replyq, ^(xpc_object_t r) {
		reply = xpc_retain(r);
		dispatch_semaphore_signal(done);
	});
	if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
		FAIL("%s: no reply within 10 s", label);
		return;
	}
	check_reply(label, conn, reply);
	xpc_release(reply);
	xpc_connection_cancel(conn);
	xpc_release(conn);
}

static void run_sync(void) {
	xpc_connection_t conn = make_connection(NULL);
	xpc_object_t reply = xpc_connection_send_message_with_reply_sync(conn, hello());
	check_reply("sync reply", conn, reply);
	xpc_release(reply);
	xpc_connection_cancel(conn);
	xpc_release(conn);
}

// The dictionary refers to the connection weakly (as the one a message handed to the event handler does): it neither
// keeps a released connection alive nor returns a stale pointer once it is gone.
static void run_weak(const char* label, int sync) {
	dispatch_semaphore_t invalid = dispatch_semaphore_create(0);
	xpc_connection_t conn = make_connection(invalid);
	__block xpc_object_t reply = NULL;
	if (sync) {
		reply = xpc_connection_send_message_with_reply_sync(conn, hello());
	} else {
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		xpc_connection_send_message_with_reply(conn, hello(), NULL, ^(xpc_object_t r) {
			reply = xpc_retain(r);
			dispatch_semaphore_signal(done);
		});
		if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
			FAIL("%s: no reply within 10 s", label);
			return;
		}
	}
	if (!is_hello_reply(reply) || remote_of(reply) != conn) {
		FAIL("%s: the reply does not report its connection to begin with", label);
		return;
	}
	xpc_connection_cancel(conn);
	if (dispatch_semaphore_wait(invalid, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
		FAIL("%s: no INVALID event within 10 s", label);
		return;
	}
	xpc_release(conn);
	for (int i = 0; i < 500 && remote_of(reply) != NULL; i++) {
		usleep(10000); // the connection is released by libxpc after the INVALID event returns
	}
	if (remote_of(reply) != NULL) {
		FAIL("%s: the reply still reports the connection 5 s after its last release (kept alive, or a stale pointer)", label);
	} else {
		printf("PASS: %s\n", label);
	}
	xpc_release(reply);
}

// an optional argument selects one case, to run it in isolation
static int selected(const char* only, const char* name) {
	return only == NULL || strcmp(only, name) == 0;
}

int main(int argc, char** argv) {
	setvbuf(stdout, NULL, _IONBF, 0);
	const char* only = argc > 1 ? argv[1] : NULL;

	if (selected(only, "local")) {
		// documented: a dictionary that was not received from a connection has no remote connection
		xpc_object_t local = xpc_dictionary_create(NULL, NULL, 0);
		if (remote_of(local) != NULL) {
			FAIL("a locally created dictionary reports a remote connection");
		} else {
			printf("PASS: local dictionary has no remote connection\n");
		}
		xpc_release(local);
	}
	if (selected(only, "async")) {
		run_async("async reply, serial reply queue", dispatch_queue_create("reply-remote-connection.reply", NULL));
		run_async("async reply, NULL reply queue", NULL);
		run_async("async reply, global concurrent queue", dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0));
	}
	if (selected(only, "sync")) {
		run_sync();
	}
	if (selected(only, "weak")) {
		run_weak("weak, async reply", 0);
		run_weak("weak, sync reply", 1);
	}
	return failures ? 1 : 0;
}
