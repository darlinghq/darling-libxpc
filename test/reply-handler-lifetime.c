// A reply handler that is still pending when the caller cancels the connection and drops its last reference must still
// run, exactly once and with an error, and the connection must not be freed under it. An anonymous listener that never
// answers and a client made from its endpoint, in one process.
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(cond, ...) do { \
	if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } \
} while (0)

static void run(dispatch_queue_t q, dispatch_queue_t replyq)
{
	dispatch_semaphore_t received = dispatch_semaphore_create(0);
	dispatch_semaphore_t handled = dispatch_semaphore_create(0);
	__block int handler_calls = 0;
	__block int handler_got_error = 0;

	xpc_connection_t listener = xpc_connection_create(NULL, q);
	__block xpc_connection_t srv_peer = NULL;
	xpc_connection_set_event_handler(listener, ^(xpc_object_t event) {
		if (xpc_get_type(event) != XPC_TYPE_CONNECTION) return;
		srv_peer = xpc_retain(event);
		xpc_connection_set_target_queue(srv_peer, q);
		xpc_connection_set_event_handler(srv_peer, ^(xpc_object_t m) {
			// never replies
			if (xpc_get_type(m) == XPC_TYPE_DICTIONARY) {
				dispatch_semaphore_signal(received);
			}
		});
		xpc_connection_resume(srv_peer);
	});
	xpc_connection_resume(listener);

	xpc_endpoint_t endpoint = xpc_endpoint_create(listener);
	xpc_connection_t client = xpc_connection_create_from_endpoint(endpoint);
	xpc_release(endpoint);
	xpc_connection_set_target_queue(client, q);
	xpc_connection_set_event_handler(client, ^(xpc_object_t e) {});
	xpc_connection_resume(client);

	xpc_object_t msg = xpc_dictionary_create(NULL, NULL, 0);
	xpc_connection_send_message_with_reply(client, msg, replyq, ^(xpc_object_t reply) {
		handler_calls++;
		handler_got_error = xpc_get_type(reply) == XPC_TYPE_ERROR;
		dispatch_semaphore_signal(handled);
	});
	xpc_release(msg);
	CHECK(dispatch_semaphore_wait(received, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0, "the listener never saw the request");

	// the caller keeps nothing: the reply handler is the only thing left that refers to the connection
	xpc_connection_cancel(client);
	xpc_release(client);

	CHECK(dispatch_semaphore_wait(handled, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0, "the pending reply handler did not run after cancel and release");
	usleep(300000); // leaves room for a second, unwanted call
	CHECK(handler_calls == 1, "the reply handler ran %d times, expected 1", handler_calls);
	CHECK(handler_got_error, "the reply handler was not given an error");

	if (srv_peer) {
		xpc_connection_cancel(srv_peer);
		xpc_release(srv_peer);
	}
	xpc_connection_cancel(listener);
	xpc_release(listener);
	dispatch_sync(q, ^{});
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	dispatch_queue_t q = dispatch_queue_create("reply-handler-lifetime", DISPATCH_QUEUE_SERIAL);
	run(q, dispatch_queue_create("reply-handler-lifetime.reply", DISPATCH_QUEUE_SERIAL));
	run(q, NULL);
	if (failures) {
		printf("%d failure(s)\n", failures);
		return 1;
	}
	puts("PASS: a pending reply handler outlives the connection's last release");
	return 0;
}
