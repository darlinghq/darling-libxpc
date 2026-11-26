// Copyright (C) 2026 Lubos Dolezel
//
// The XPC services that a framework holds (in an XPCServices directory next to
// its binary) can be reached by name from a process once it has loaded the
// framework, even with dlopen() at run time; before that they can't, and a
// name no loaded bundle has stays unknown. Observed on macOS 26.7.3 (x86_64),
// with WebKit's services and with this test's framework.
//
//   framework-xpc-services [<path of XPCTestFramework.framework>]
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

#define SERVICE "org.darlinghq.libxpc-test.framework-service"

static int failures;
#define CHECK(cond, ...) do { \
	if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } \
} while (0)

// Sends a message to the named service and returns its reply (or the error
// the reply handler got); NULL when nothing came in time.
static xpc_object_t ask(const char *name)
{
	xpc_connection_t connection = xpc_connection_create(name, NULL);
	xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {});
	xpc_connection_resume(connection);

	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	__block xpc_object_t result = NULL;
	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_string(message, "value", "hello");
	xpc_connection_send_message_with_reply(connection, message, NULL, ^(xpc_object_t reply) {
		result = xpc_retain(reply);
		dispatch_semaphore_signal(done);
	});
	xpc_release(message);
	dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
	xpc_connection_cancel(connection);
	xpc_release(connection);
	dispatch_release(done);
	return result;
}

int main(int argc, char **argv)
{
	const char *framework = argc > 1 ? argv[1] : "/usr/libexec/test/xpc/XPCTestFramework.framework";
	char binary[1024];
	snprintf(binary, sizeof(binary), "%s/XPCTestFramework", framework);

	xpc_object_t reply = ask(SERVICE);
	CHECK(reply == XPC_ERROR_CONNECTION_INVALID, "the service is found before the framework is loaded");

	void *handle = dlopen(binary, RTLD_NOW);
	CHECK(handle != NULL, "the framework doesn't load: %s", dlerror());

	reply = ask(SERVICE);
	CHECK(reply && xpc_get_type(reply) == XPC_TYPE_DICTIONARY, "the framework's service doesn't answer once the framework is loaded");
	if (reply && xpc_get_type(reply) == XPC_TYPE_DICTIONARY) {
		const char *echo = xpc_dictionary_get_string(reply, "echo");
		CHECK(echo && strcmp(echo, "hello") == 0, "the service's reply is wrong");
	}

	reply = ask("org.darlinghq.libxpc-test.no-such-service");
	CHECK(reply == XPC_ERROR_CONNECTION_INVALID, "an unknown name doesn't fail as invalid");

	if (failures == 0)
		printf("PASS\n");
	return failures != 0;
}
