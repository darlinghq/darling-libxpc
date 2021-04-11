#ifndef _XPC_PRIVATE_PIPE_H_
#define _XPC_PRIVATE_PIPE_H_

// NOTE: i have no clue if this header exists in the real libxpc,
//       but it seems logical to keep all the xpc_pipe stuff in one place
//       (rather than dumping it all into `private.h`)

#include <xpc/xpc.h>

#ifdef __cplusplus
extern "C" {
#endif

XPC_IGNORE_DUPLICATE_PROTOCOL_PUSH;
XPC_DECL(xpc_pipe);
XPC_IGNORE_DUPLICATE_PROTOCOL_POP;

// verified correct
#define XPC_PIPE_PRIVILEGED (1 << 1)
#define XPC_PIPE_USE_SYNC_IPC_OVERRIDE (1 << 2)

// not sure what these are called or what they do, but they definitely exist
#define XPC_PIPE_SOME_OTHER_FLAG_1 (1 << 3)
#define XPC_PIPE_SOME_OTHER_FLAG_2 (1 << 4)

#define XPC_PIPE_FLAG_PRIVILEGED XPC_PIPE_PRIVILEGED

// not sure about the name, but i'm sure of the value and purpose
#define XPC_PIPE_RECEIVE_FLAG_NONBLOCKING (1 << 0)

xpc_pipe_t xpc_pipe_create(const char* name, uint64_t flags);
xpc_pipe_t xpc_pipe_create_from_port(mach_port_t port, uint64_t flags);

void xpc_pipe_invalidate(xpc_pipe_t xpipe);

int xpc_pipe_routine(xpc_pipe_t xpipe, xpc_object_t xdict, xpc_object_t* reply);
int xpc_pipe_routine_with_flags(xpc_pipe_t xpipe, xpc_object_t xdict, xpc_object_t* reply, uint64_t flags);
int xpc_pipe_routine_reply(xpc_object_t xdict);
int xpc_pipe_routine_async(xpc_pipe_t xpipe, xpc_object_t xdict, mach_port_t local_reply_port);
int xpc_pipe_routine_forward(xpc_pipe_t xpipe, xpc_object_t xdict);
int xpc_pipe_simpleroutine(xpc_pipe_t xpipe, xpc_object_t xdict);

int xpc_pipe_receive(mach_port_t receive_port, xpc_object_t* out_msg, uint64_t flags);
int xpc_pipe_try_receive(mach_port_t port, xpc_object_t* out_object, mach_port_t* out_local_port, boolean_t (*demuxer)(mach_msg_header_t* request, mach_msg_header_t* reply), mach_msg_size_t max_mig_reply_size, uint64_t flags);

int _xpc_pipe_handle_mig(mach_msg_header_t* request, mach_msg_header_t* reply, boolean_t (*demuxer)(mach_msg_header_t* request, mach_msg_header_t* reply));

#ifdef __cplusplus
};
#endif

#endif // _XPC_PRIVATE_PIPE_H_