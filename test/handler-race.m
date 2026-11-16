// Plain-guest stress test: the event handler of a connection is replaced from the main thread while the connection's
// own queue delivers XPC_ERROR_CONNECTION_INVALID to it (the connection names a service that does not exist, so the
// event is delivered right after resume). Every handler block captures its own canary object; a handler that runs
// after its block was freed (a replacement released it between the read and the retain) sees a dead canary.
#import <objc/NSObject.h>
#include <Block.h>
#include <dispatch/dispatch.h>
#include <xpc/xpc.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

#define ITERATIONS 10000
#define MAGIC 0x5a5a5a5a

static volatile int g_bad, g_handled;

@interface Canary : NSObject { @public int alive; }
@end
@implementation Canary
- (id)init { if ((self = [super init])) alive = MAGIC; return self; }
- (void)dealloc { alive = 0; [super dealloc]; }
@end

// installs a fresh handler whose block captures its own canary
static void set_fresh_handler(xpc_connection_t conn, dispatch_semaphore_t done) {
	Canary *canary = [[Canary alloc] init];
	xpc_handler_t handler = ^(xpc_object_t event) {
		if (event != XPC_ERROR_CONNECTION_INVALID) return;
		if (canary->alive != MAGIC) g_bad = 1;
		g_handled++;
		dispatch_semaphore_signal(done);
	};
	xpc_handler_t heap = Block_copy(handler); // a block literal is a stack block until copied
	[canary release];
	xpc_connection_set_event_handler(conn, heap);
	Block_release(heap);
}

int main(void) {
	setvbuf(stdout, NULL, _IONBF, 0);
	dispatch_queue_t q = dispatch_queue_create("race", NULL);
	for (int i = 0; i < ITERATIONS; i++) {
		char name[128];
		snprintf(name, sizeof name, "org.darlinghq.test.handler-race.%d.%d", (int)getpid(), i);
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		xpc_connection_t conn = xpc_connection_create_mach_service(name, q, 0);
		set_fresh_handler(conn, done);
		xpc_connection_resume(conn);
		// keep replacing the handler from this thread until the event was delivered on q
		time_t start = time(NULL);
		while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW)) {
			set_fresh_handler(conn, done);
			usleep(20); // the handler lock is not fair: do not starve the delivering thread
			if (time(NULL) - start > 30) {
				fprintf(stderr, "FAIL: handler-race: no INVALID event on iteration %d\n", i);
				return 1;
			}
		}
		dispatch_sync(q, ^{});
		xpc_release(conn);
		if (g_bad) {
			fprintf(stderr, "FAIL: handler-race: a handler ran with its captured object already freed (iteration %d)\n", i);
			return 1;
		}
	}
	if (g_handled != ITERATIONS) {
		fprintf(stderr, "FAIL: handler-race: %d handler runs for %d events\n", g_handled, ITERATIONS);
		return 1;
	}
	printf("PASS: handler-race (%d events delivered while the handler was being replaced)\n", ITERATIONS);
	return 0;
}
