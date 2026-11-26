// Copyright (C) 2026 Lubos Dolezel
//
// A message sent with xpc_connection_send_message_with_reply() whose reply is
// still pending when the last reference to the connection is released: the
// reply handler is still called exactly once, with an error. Observed on
// macOS 26.7.3 (x86_64) with the same calls:
//
// - a service that doesn't exist: XPC_ERROR_CONNECTION_INVALID;
// - a peer that never replies, connection canceled and released:
//   XPC_ERROR_CONNECTION_INVALID;
// - the same, released without canceling: XPC_ERROR_CONNECTION_INTERRUPTED.
//   (Darling gives XPC_ERROR_CONNECTION_INVALID here; the test only requires
//   an error.)
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(cond, ...) do { \
	if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } \
} while (0)

// Sends a message expecting a reply, releases the connection (canceling it
// first if asked) and returns the reply handler's argument; counts the calls.
static xpc_object_t send_and_release(xpc_connection_t connection, int cancel, int *calls)
{
	dispatch_semaphore_t called = dispatch_semaphore_create(0);
	__block xpc_object_t result = NULL;
	__block int count = 0;

	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_int64(message, "x", 1);
	xpc_connection_send_message_with_reply(connection, message, NULL, ^(xpc_object_t reply) {
		count++;
		result = reply;
		dispatch_semaphore_signal(called);
	});
	xpc_release(message);
	if (cancel)
		xpc_connection_cancel(connection);
	xpc_release(connection);

	dispatch_semaphore_wait(called, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
	// time for a second, wrong call to show up
	usleep(200000);
	*calls = count;
	dispatch_release(called);
	return result;
}

static xpc_connection_t silent_peer_client(void)
{
	xpc_connection_t listener = xpc_connection_create(NULL, NULL);
	xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
		if (xpc_get_type(peer) != XPC_TYPE_CONNECTION)
			return;
		// kept, and never replies
		xpc_retain(peer);
		xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {});
		xpc_connection_resume(peer);
	});
	xpc_connection_resume(listener);

	xpc_endpoint_t endpoint = xpc_endpoint_create(listener);
	xpc_connection_t client = xpc_connection_create_from_endpoint(endpoint);
	xpc_release(endpoint);
	xpc_connection_set_event_handler(client, ^(xpc_object_t event) {});
	xpc_connection_resume(client);
	return client;
}

int main(void)
{
	int calls;
	xpc_object_t reply;

	xpc_connection_t missing = xpc_connection_create_mach_service("org.darlinghq.libxpc-test.does-not-exist", NULL, 0);
	xpc_connection_set_event_handler(missing, ^(xpc_object_t event) {});
	xpc_connection_resume(missing);
	reply = send_and_release(missing, 0, &calls);
	CHECK(calls == 1, "missing service: the handler was called %d times", calls);
	CHECK(reply == XPC_ERROR_CONNECTION_INVALID, "missing service: the handler didn't get XPC_ERROR_CONNECTION_INVALID");

	reply = send_and_release(silent_peer_client(), 1, &calls);
	CHECK(calls == 1, "canceled: the handler was called %d times", calls);
	CHECK(reply == XPC_ERROR_CONNECTION_INVALID, "canceled: the handler didn't get XPC_ERROR_CONNECTION_INVALID");

	reply = send_and_release(silent_peer_client(), 0, &calls);
	CHECK(calls == 1, "released: the handler was called %d times", calls);
	CHECK(reply == XPC_ERROR_CONNECTION_INVALID || reply == XPC_ERROR_CONNECTION_INTERRUPTED,
	      "released: the handler didn't get a connection error");

	if (failures == 0)
		printf("PASS\n");
	return failures != 0;
}
