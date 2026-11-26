// Needs the launchd test service (launchd-service/, plist installed with the tests) to be registered.
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <bootstrap.h>
#include <xpc/xpc.h>
#include <stdio.h>
#include <unistd.h>

#include "launchd-service/service.h"

// private API under test; declared here because the SDK does not ship it
xpc_endpoint_t xpc_endpoint_create_bs_named(const char* name, uint64_t flags, uint8_t* out_type);

static int send_refs(mach_port_t port) {
	mach_port_urefs_t refs = 0;
	return mach_port_get_refs(mach_task_self(), port, MACH_PORT_RIGHT_SEND, &refs) == KERN_SUCCESS ? (int)refs : -1;
}

int main(void) {
	setvbuf(stdout, NULL, _IONBF, 0);
	char missing[160];
	snprintf(missing, sizeof(missing), "org.darlinghq.test.no-such-service.%ld", (long)getpid());

	uint8_t type = 0xAA;
	if (xpc_endpoint_create_bs_named(missing, 0, &type) != NULL) {
		fprintf(stderr, "FAIL: an endpoint was returned for a service that does not exist\n");
		return 1;
	}

	// defensive guard: bootstrap_look_up(NULL) fails without crashing too, but the result must be NULL either way
	if (xpc_endpoint_create_bs_named(NULL, 0, &type) != NULL) {
		fprintf(stderr, "FAIL: an endpoint was returned for a NULL name\n");
		return 1;
	}

	// the out parameter is optional
	xpc_endpoint_t no_type = xpc_endpoint_create_bs_named(TEST_SERVICE_NAME, 0, NULL);
	if (no_type == NULL) {
		fprintf(stderr, "FAIL: no endpoint for the registered service when out_type is NULL\n");
		return 1;
	}
	xpc_release(no_type);

	// each endpoint owns exactly the one send right bootstrap_look_up gave it: creating and releasing many must leave
	// our own right to the same port unchanged (a missed release leaks rights, an extra release steals ours)
	mach_port_t own = MACH_PORT_NULL;
	if (bootstrap_look_up(bootstrap_port, TEST_SERVICE_NAME, &own) != KERN_SUCCESS) {
		fprintf(stderr, "FAIL: look up of the registered service failed\n");
		return 1;
	}
	int before = send_refs(own);
	for (int i = 0; i < 200; i++) {
		xpc_endpoint_t e = xpc_endpoint_create_bs_named(TEST_SERVICE_NAME, 0, &type);
		if (e == NULL) {
			fprintf(stderr, "FAIL: no endpoint on iteration %d\n", i);
			return 1;
		}
		xpc_release(e);
	}
	int after = send_refs(own);
	if (before != after) {
		fprintf(stderr, "FAIL: send right urefs %d before, %d after 200 endpoint create/release\n", before, after);
		return 1;
	}

	type = 0xAA;
	xpc_endpoint_t endpoint = xpc_endpoint_create_bs_named(TEST_SERVICE_NAME, 0, &type);
	if (endpoint == NULL) {
		fprintf(stderr, "FAIL: no endpoint for the registered service %s\n", TEST_SERVICE_NAME);
		return 1;
	}
	// QUIRK pinned: the out type of a found service is 2 (observed on macOS 26.7.3, see endpoint.m)
	if (type != 2) {
		fprintf(stderr, "FAIL: the out type parameter is %d, expected 2\n", type);
		return 1;
	}

	dispatch_queue_t queue = dispatch_queue_create("bs-named", NULL);
	dispatch_semaphore_t replied = dispatch_semaphore_create(0);
	__block int reply_type_ok = 0;
	xpc_connection_t connection = xpc_connection_create_from_endpoint(endpoint);
	xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {});
	xpc_connection_resume(connection);

	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_uint64(message, MESSAGE_TYPE_KEY, test_service_message_type_hello);
	xpc_dictionary_set_string(message, HELLO_KEY, "hello through a bs-named endpoint");
	xpc_connection_send_message_with_reply(connection, message, queue, ^(xpc_object_t reply) {
		reply_type_ok = xpc_get_type(reply) == XPC_TYPE_DICTIONARY &&
			xpc_dictionary_get_uint64(reply, MESSAGE_TYPE_KEY) == test_service_message_type_hello;
		dispatch_semaphore_signal(replied);
	});
	xpc_release(message);

	if (dispatch_semaphore_wait(replied, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
		fprintf(stderr, "FAIL: no reply from the service through its endpoint within 10 s\n");
		return 1;
	}
	if (!reply_type_ok) {
		fprintf(stderr, "FAIL: the reply was not the service's hello reply\n");
		return 1;
	}
	puts("PASS: bs-named endpoint reaches the registered service, missing service gives NULL");
	return 0;
}
