/**
 * This file is part of Darling.
 *
 * Copyright (C) 2023 Darling developers
 *
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Darling is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */


#ifndef __XPC_CONNECTION_H__
#define __XPC_CONNECTION_H__

#ifndef __XPC_INDIRECT__
#error "It's not recommended to directly include <xpc/connection.h>, please #include <xpc/xpc.h> instead."
#endif

#include <xpc/base.h>

__BEGIN_DECLS

#define XPC_CONNECTION_MACH_SERVICE_LISTENER (1 << 0)
#define XPC_CONNECTION_MACH_SERVICE_PRIVILEGED (1 << 1)

XPC_EXPORT const struct _xpc_dictionary_s _xpc_error_connection_interrupted;
XPC_EXPORT const struct _xpc_dictionary_s _xpc_error_connection_invalid;
XPC_EXPORT const struct _xpc_dictionary_s _xpc_error_termination_imminent;

#define XPC_ERROR_CONNECTION_INTERRUPTED XPC_GLOBAL_OBJECT(_xpc_error_connection_interrupted)
#define XPC_ERROR_CONNECTION_INVALID XPC_GLOBAL_OBJECT(_xpc_error_connection_invalid)
#define XPC_ERROR_TERMINATION_IMMINENT XPC_GLOBAL_OBJECT(_xpc_error_termination_imminent)

typedef void (*xpc_finalizer_t)(void *value);

void xpc_connection_activate(xpc_connection_t connection);
void xpc_connection_cancel(xpc_connection_t connection);
xpc_connection_t xpc_connection_create(const char *name, dispatch_queue_t targetq);
xpc_connection_t xpc_connection_create_from_endpoint(xpc_endpoint_t endpoint);
xpc_connection_t xpc_connection_create_mach_service(const char *name, dispatch_queue_t targetq, uint64_t flags);
au_asid_t xpc_connection_get_asid(xpc_connection_t connection);
void * xpc_connection_get_context(xpc_connection_t connection);
gid_t xpc_connection_get_egid(xpc_connection_t connection);
uid_t xpc_connection_get_euid(xpc_connection_t connection);
const char * xpc_connection_get_name(xpc_connection_t connection);
pid_t xpc_connection_get_pid(xpc_connection_t connection);
void xpc_connection_resume(xpc_connection_t connection);
void xpc_connection_send_message(xpc_connection_t connection, xpc_object_t message);
void xpc_connection_send_message_with_reply(xpc_connection_t connection, xpc_object_t message, dispatch_queue_t replyq, xpc_handler_t handler);
xpc_object_t xpc_connection_send_message_with_reply_sync(xpc_connection_t connection, xpc_object_t message);
void xpc_connection_set_context(xpc_connection_t connection, void *context);
void xpc_connection_set_event_handler(xpc_connection_t connection, xpc_handler_t handler);
void xpc_connection_set_finalizer_f(xpc_connection_t connection, xpc_finalizer_t finalizer);
void xpc_connection_set_target_queue(xpc_connection_t connection, dispatch_queue_t targetq);
void xpc_connection_suspend(xpc_connection_t connection);

__END_DECLS

#endif // __XPC_CONNECTION_H__ 
