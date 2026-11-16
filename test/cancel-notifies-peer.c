// Copyright (C) 2026 Lubos Dolezel
//
// xpc_connection_cancel() makes the connection invalid at once, whether or
// not the caller still holds a reference: the other end gets
// XPC_ERROR_CONNECTION_INVALID without waiting for the last xpc_release, and
// the canceling side's own handler gets it exactly once and nothing after.
// An anonymous listener and a client made from its endpoint, in one process.
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(cond, ...) do { \
	if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } \
} while (0)

static dispatch_queue_t q;
static dispatch_semaphore_t srv_invalid_sem;
static dispatch_semaphore_t cli_invalid_sem;
// all counters are only touched on q
static int srv_invalid, srv_events_after_invalid, cli_invalid, cli_events_after_invalid;
static xpc_connection_t srv_peer;

static void run(int cancel_twice)
{
	srv_invalid = srv_events_after_invalid = cli_invalid = cli_events_after_invalid = 0;
	srv_invalid_sem = dispatch_semaphore_create(0);
	cli_invalid_sem = dispatch_semaphore_create(0);
	dispatch_semaphore_t connected = dispatch_semaphore_create(0);

	xpc_connection_t listener = xpc_connection_create(NULL, q);
	xpc_connection_set_event_handler(listener, ^(xpc_object_t event) {
		if (xpc_get_type(event) != XPC_TYPE_CONNECTION) return;
		srv_peer = event;
		xpc_retain(srv_peer);
		xpc_connection_set_target_queue(srv_peer, q);
		xpc_connection_set_event_handler(srv_peer, ^(xpc_object_t m) {
			if (srv_invalid) srv_events_after_invalid++;
			if (xpc_get_type(m) == XPC_TYPE_DICTIONARY) {
				xpc_object_t r = xpc_dictionary_create_reply(m);
				xpc_connection_send_message(srv_peer, r);
				xpc_release(r);
				dispatch_semaphore_signal(connected);
			} else if (m == XPC_ERROR_CONNECTION_INVALID) {
				srv_invalid++;
				dispatch_semaphore_signal(srv_invalid_sem);
			}
		});
		xpc_connection_resume(srv_peer);
	});
	xpc_connection_resume(listener);

	xpc_endpoint_t endpoint = xpc_endpoint_create(listener);
	xpc_connection_t client = xpc_connection_create_from_endpoint(endpoint);
	xpc_connection_set_target_queue(client, q);
	xpc_connection_set_event_handler(client, ^(xpc_object_t e) {
		if (cli_invalid) cli_events_after_invalid++;
		if (e == XPC_ERROR_CONNECTION_INVALID) {
			cli_invalid++;
			dispatch_semaphore_signal(cli_invalid_sem);
		}
	});
	xpc_connection_resume(client);

	xpc_object_t msg = xpc_dictionary_create(NULL, NULL, 0);
	xpc_object_t reply = xpc_connection_send_message_with_reply_sync(client, msg);
	CHECK(xpc_get_type(reply) == XPC_TYPE_DICTIONARY, "round trip before cancel failed");
	xpc_release(reply);
	xpc_release(msg);
	CHECK(dispatch_semaphore_wait(connected, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0, "server never saw the request");

	// cancel while still holding the reference
	xpc_connection_cancel(client);
	CHECK(dispatch_semaphore_wait(srv_invalid_sem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0,
		"server side saw no XPC_ERROR_CONNECTION_INVALID within 2 s of the client's cancel (reference still held)");
	CHECK(dispatch_semaphore_wait(cli_invalid_sem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0,
		"canceling side got no XPC_ERROR_CONNECTION_INVALID");

	if (cancel_twice) {
		xpc_connection_cancel(client);
	}
	// sending on a cancelled connection must fail quietly
	xpc_object_t late = xpc_dictionary_create(NULL, NULL, 0);
	xpc_connection_send_message(client, late);
	xpc_release(late);
	usleep(300000);

	// releasing afterwards must not crash or produce further events
	xpc_release(client);
	usleep(300000);
	dispatch_sync(q, ^{
		CHECK(cli_invalid == 1, "canceling side's handler got %d invalid events, expected 1", cli_invalid);
		CHECK(cli_events_after_invalid == 0, "canceling side's handler got %d events after invalid", cli_events_after_invalid);
		CHECK(srv_invalid == 1, "server side got %d invalid events, expected 1", srv_invalid);
		CHECK(srv_events_after_invalid == 0, "server side got %d events after invalid", srv_events_after_invalid);
	});

	xpc_connection_cancel(srv_peer);
	xpc_release(srv_peer);
	xpc_connection_cancel(listener);
	xpc_release(listener);
	dispatch_sync(q, ^{});
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	q = dispatch_queue_create("cancel-test", DISPATCH_QUEUE_SERIAL);
	run(0);
	run(1);
	if (failures) {
		printf("%d failure(s)\n", failures);
		return 1;
	}
	puts("PASS: cancel notifies the peer while the reference is held");
	return 0;
}
