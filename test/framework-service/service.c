// Copyright (C) 2026 Lubos Dolezel
//
// The XPC service inside XPCTestFramework.framework, for
// framework-xpc-services.c and framework-xpc-instances.c: it answers every
// message with a reply holding "echo" = the message's "value" and "pid" = its
// process ID.
#include <xpc/xpc.h>
#include <unistd.h>

static void connection_handler(xpc_connection_t connection)
{
	xpc_connection_set_event_handler(connection, ^(xpc_object_t message) {
		if (xpc_get_type(message) != XPC_TYPE_DICTIONARY)
			return;
		xpc_object_t reply = xpc_dictionary_create_reply(message);
		if (!reply)
			return;
		xpc_dictionary_set_string(reply, "echo", xpc_dictionary_get_string(message, "value"));
		xpc_dictionary_set_int64(reply, "pid", getpid());
		xpc_connection_send_message(connection, reply);
		xpc_release(reply);
	});
	xpc_connection_resume(connection);
}

int main(void)
{
	xpc_main(connection_handler);
}
