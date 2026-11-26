// Plain-guest test. A client object whose dealloc asserts "must be invalidated before deallocation" (the pattern of a
// service client) is captured by a connection event handler.
//   plain / reset: the connection names a service that does not exist, so the handler gets XPC_ERROR_CONNECTION_INVALID.
//                  "reset" replaces the handler from inside the handler (breaking its own retain cycle) and THEN
//                  invalidates the client; "plain" just invalidates it.
//   no-handler:    a connection that never got an event handler must survive the event (it is logged and dropped).
// The client must be deallocated exactly once, after it was invalidated and after the handler body finished.
#import <objc/NSObject.h>
#include <dispatch/dispatch.h>
#include <xpc/xpc.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static volatile int g_bad, g_deallocs, g_handler_done;
static const char *g_label = "";

@interface Client : NSObject { @public int invalidated; }
- (void)invalidate;
@end
@implementation Client
- (void)invalidate { invalidated = 1; }
- (void)dealloc {
	g_deallocs++;
	if (!invalidated) {
		fprintf(stderr, "FAIL: %s: Client must be invalidated before deallocation (handler finished: %d)\n", g_label, g_handler_done);
		g_bad = 1;
	}
	[super dealloc];
}
@end

static void begin(const char *label) { g_label = label; g_deallocs = 0; g_bad = 0; g_handler_done = 0; }

static int finish(void) {
	for (int i = 0; i < 500 && g_deallocs == 0; i++) usleep(10000); // the final release runs after the handler returns
	if (g_deallocs != 1) { fprintf(stderr, "FAIL: %s: client dealloc count %d, expected 1\n", g_label, g_deallocs); return 1; }
	if (g_bad) return 1;
	printf("PASS: %s\n", g_label);
	return 0;
}

static int run_invalid(const char *label, int reset) {
	begin(label);
	char name[128];
	snprintf(name, sizeof name, "org.darlinghq.test.handler-lifetime.%s.%d", label, (int)getpid());
	dispatch_queue_t q = dispatch_queue_create("probe", NULL);
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	Client *client = [[Client alloc] init];
	xpc_connection_t conn = xpc_connection_create_mach_service(name, q, 0);
	xpc_connection_set_event_handler(conn, ^(xpc_object_t event) {
		if (event == XPC_ERROR_CONNECTION_INVALID) {
			if (reset) xpc_connection_set_event_handler(conn, ^(xpc_object_t e) {});
			[client invalidate];
			g_handler_done = 1;
			dispatch_semaphore_signal(done);
		}
	});
	[client release]; // the handler holds the only reference
	xpc_connection_resume(conn);
	if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
		fprintf(stderr, "FAIL: %s: no INVALID event within 10 s\n", label);
		return 1;
	}
	dispatch_sync(q, ^{});
	xpc_release(conn);
	return finish();
}

static int run_no_handler(void) {
	begin("no-handler");
	char name[128];
	snprintf(name, sizeof name, "org.darlinghq.test.handler-lifetime.no-handler.%d", (int)getpid());
	dispatch_queue_t q = dispatch_queue_create("probe-no-handler", NULL);
	xpc_connection_t conn = xpc_connection_create_mach_service(name, q, 0);
	xpc_connection_resume(conn); // INVALID is delivered to a connection that has no handler
	usleep(300000);
	dispatch_sync(q, ^{});
	printf("PASS: %s\n", g_label);
	return 0;
}

int main(void) {
	setvbuf(stdout, NULL, _IONBF, 0);
	int rc = 0;
	rc |= run_invalid("plain", 0);
	rc |= run_invalid("reset", 1);
	rc |= run_no_handler();
	return rc;
}
