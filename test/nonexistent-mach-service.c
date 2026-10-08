#include <dispatch/dispatch.h>
#include <xpc/xpc.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

static char queue_key;

int main(void) {
    char name[160];
    snprintf(name, sizeof(name), "org.darlinghq.test.nonexistent.%ld.%ld",
        (long)getpid(), (long)time(NULL));
    dispatch_queue_t queue = dispatch_queue_create("missing-service-events", NULL);
    dispatch_semaphore_t received = dispatch_semaphore_create(0);
    dispatch_queue_set_specific(queue, &queue_key, &queue_key, NULL);
    __block int invalid = 0;
    __block int correct_queue = 0;
    xpc_connection_t connection = xpc_connection_create_mach_service(name, queue, 0);
    if (!connection) {
        fprintf(stderr, "FAIL: connection creation returned NULL\n");
        return 1;
    }
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        invalid = event == XPC_ERROR_CONNECTION_INVALID;
        correct_queue = dispatch_get_specific(&queue_key) == &queue_key;
        dispatch_semaphore_signal(received);
    });
    puts("probe: handler installed; resuming synthetic local connection");
    fflush(stdout);
    xpc_connection_resume(connection);
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_bool(message, "synthetic", true);
    xpc_connection_send_message(connection, message);
    xpc_release(message);
    long timed_out = dispatch_semaphore_wait(received,
        dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    if (timed_out) {
        fprintf(stderr, "FAIL: no event within test deadline\n");
        return 1;
    }
    dispatch_sync(queue, ^{});
    xpc_release(connection);
    dispatch_release(received);
    dispatch_release(queue);
    if (!invalid || !correct_queue) {
        fprintf(stderr, "FAIL: invalid=%d target_queue=%d\n", invalid, correct_queue);
        return 1;
    }
    puts("PASS: nonexistent local service delivered INVALID on target queue");
    return 0;
}
