// Copyright (C) 2026 Lubos Dolezel
//
// An XPC service that declares _MultipleInstances runs one process per
// instance: connections given the same instance UUID (with
// xpc_connection_set_oneshot_instance or xpc_connection_set_instance) reach
// the same process, different UUIDs reach different processes, and
// connections without a UUID share one more process. xpc_connection_kill()
// signals the process at the other end of a connection; after it is gone, a
// new connection with its UUID starts a new process. Observed on macOS
// 26.7.3 (x86_64).
//
//   framework-xpc-instances [<path of XPCTestFramework.framework>]
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>
#include <uuid/uuid.h>

// Private libxpc API.
void xpc_connection_set_oneshot_instance(xpc_connection_t connection, const uuid_t instance);
void xpc_connection_set_instance(xpc_connection_t connection, uuid_t instance);
void xpc_connection_kill(xpc_connection_t connection, int signal);

#define SERVICE "org.darlinghq.libxpc-test.framework-instance-service"

static int failures;
#define CHECK(cond, ...) do { \
	if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } \
} while (0)

enum { NO_INSTANCE, ONESHOT, PERSISTENT };

static xpc_connection_t connect_to(int kind, uuid_t instance)
{
	xpc_connection_t connection = xpc_connection_create(SERVICE, NULL);
	if (kind == ONESHOT)
		xpc_connection_set_oneshot_instance(connection, instance);
	else if (kind == PERSISTENT)
		xpc_connection_set_instance(connection, instance);
	xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {});
	xpc_connection_resume(connection);
	return connection;
}

// The process ID the service reports, or -1 when it doesn't answer.
static pid_t service_pid(xpc_connection_t connection)
{
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	__block pid_t pid = -1;
	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_string(message, "value", "pid");
	xpc_connection_send_message_with_reply(connection, message, NULL, ^(xpc_object_t reply) {
		if (xpc_get_type(reply) == XPC_TYPE_DICTIONARY)
			pid = (pid_t)xpc_dictionary_get_int64(reply, "pid");
		dispatch_semaphore_signal(done);
	});
	xpc_release(message);
	dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
	dispatch_release(done);
	return pid;
}

static int process_exists(pid_t pid)
{
	return kill(pid, 0) == 0 || errno != ESRCH;
}

int main(int argc, char **argv)
{
	const char *framework = argc > 1 ? argv[1] : "/usr/libexec/test/xpc/XPCTestFramework.framework";
	char binary[1024];
	snprintf(binary, sizeof(binary), "%s/XPCTestFramework", framework);
	if (!dlopen(binary, RTLD_NOW)) {
		printf("FAIL: the framework doesn't load: %s\n", dlerror());
		return 1;
	}

	uuid_t first, second;
	uuid_generate(first);
	uuid_generate(second);

	xpc_connection_t a = connect_to(ONESHOT, first);
	xpc_connection_t b = connect_to(ONESHOT, second);
	xpc_connection_t a2 = connect_to(ONESHOT, first);
	xpc_connection_t b2 = connect_to(PERSISTENT, second);
	xpc_connection_t plain = connect_to(NO_INSTANCE, NULL);
	xpc_connection_t plain2 = connect_to(NO_INSTANCE, NULL);

	pid_t pa = service_pid(a), pb = service_pid(b), pa2 = service_pid(a2);
	pid_t pb2 = service_pid(b2), pplain = service_pid(plain), pplain2 = service_pid(plain2);
	CHECK(pa > 0 && pb > 0 && pa2 > 0 && pb2 > 0 && pplain > 0 && pplain2 > 0,
		"a service process doesn't answer (%d %d %d %d %d %d)", pa, pb, pa2, pb2, pplain, pplain2);
	CHECK(pa != getpid() && pa != pb, "two instances share a process (%d, %d)", pa, pb);
	CHECK(pa == pa2, "one instance runs in two processes (%d, %d)", pa, pa2);
	CHECK(pb == pb2, "xpc_connection_set_instance reaches another process than the oneshot instance with its UUID (%d, %d)", pb, pb2);
	CHECK(pplain == pplain2, "connections without an instance reach different processes (%d, %d)", pplain, pplain2);
	CHECK(pplain != pa && pplain != pb, "connections without an instance reach an instance's process");

	if (pb > 0) {
		xpc_connection_kill(b, SIGKILL);
		int gone = 0;
		for (int i = 0; i < 50 && !gone; i++) {
			gone = !process_exists(pb);
			if (!gone)
				usleep(100000);
		}
		CHECK(gone, "xpc_connection_kill doesn't end the service process %d", pb);
		CHECK(pa > 0 && process_exists(pa), "killing one instance ends another");

		xpc_connection_t again = connect_to(ONESHOT, second);
		pid_t pagain = service_pid(again);
		CHECK(pagain > 0 && pagain != pb, "a new connection to a killed instance gets no new process (%d)", pagain);
		xpc_connection_cancel(again);
		xpc_release(again);
	}

	xpc_connection_t all[] = { a, b, a2, b2, plain, plain2 };
	for (size_t i = 0; i < sizeof(all) / sizeof(all[0]); i++) {
		xpc_connection_cancel(all[i]);
		xpc_release(all[i]);
	}

	printf(failures ? "FAILED\n" : "PASSED\n");
	return failures != 0;
}
