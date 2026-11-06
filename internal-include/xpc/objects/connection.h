/**
 * This file is part of Darling.
 *
 * Copyright (C) 2021 Darling developers
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

#ifndef _XPC_OBJECTS_CONNECTION_H_
#define _XPC_OBJECTS_CONNECTION_H_

// ensure libdispatch exposes libxpc SPI
#define DISPATCH_MACH_SPI 1
#include <dispatch/dispatch.h>
#ifndef __DISPATCH_INDIRECT__
#define __DISPATCH_INDIRECT__ 1
#endif
#include <dispatch/mach_private.h>

#import <xpc/objects/base.h>
#import <xpc/xpc.h>
#import <xpc/connection.h>
#import <xpc/generic_array.h>

#include <stdatomic.h>

XPC_IGNORE_DUPLICATE_PROTOCOL_PUSH;
XPC_CLASS_DECL(connection);
XPC_IGNORE_DUPLICATE_PROTOCOL_POP;

@class XPC_CLASS(connection);
@class XPC_CLASS(dictionary);
@class XPC_CLASS(endpoint);

typedef struct xpc_connection_reply_context_s {
	xpc_handler_t handler;
	dispatch_queue_t queue;
} xpc_connection_reply_context_t;

XPC_GENARR_DECL(connection, XPC_CLASS(connection)*, /* non-static */);
XPC_GENARR_SEARCH_DECL(connection, XPC_CLASS(connection)*, /* non-static */);
XPC_GENARR_BLOCKS_DECL(connection, XPC_CLASS(connection)*, /* non-static */);
XPC_GENARR_STRUCT(connection, XPC_CLASS(connection)*);

struct xpc_connection_s {
	struct xpc_object_s base;

	//
	// immutable after init
	//
	bool is_listener;
	bool is_server_peer;
	const char* service_name;
	XPC_CLASS(connection)* parent_server;

	//
	// immutable after activation
	//
	mach_port_t recv_port;
	mach_port_t checkin_port;

	//
	// mutable only when locked
	//
	pthread_rwlock_t activated_lock;
	bool activated;
	pthread_rwlock_t server_peers_lock;
	xpc_genarr_connection_t server_peers;
	pthread_rwlock_t remote_credentials_lock;

	audit_token_t remote_credentials;

	//
	// mutable and lock-free
	//
	dispatch_mach_t mach_ctx;
	void* user_context;
	xpc_handler_t event_handler;
	xpc_finalizer_t finalizer;
	atomic_intmax_t suspension_count;
	bool is_cancelled;
	// set when the named service couldn't be looked up; the connection is invalid, not interrupted
	bool lookup_failed;

	//
	// other
	// (each one has it's own explaination)
	//

	// immutable most of the time and can be treated as such.
	// only mutated when the connection is (re)activated
	mach_port_t send_port;
};

@interface XPC_CLASS_INTERFACE(connection)

@property(assign) void* userContext;
@property(readonly) const char* serviceName;
@property(copy) xpc_handler_t eventHandler;
@property(assign) xpc_finalizer_t finalizer;
@property(readonly) mach_port_t sendPort;
@property(readonly) mach_port_t receivePort;
@property(strong) dispatch_queue_t targetQueue;
@property(assign /* actually weak */) XPC_CLASS(connection)* parentServer;

- (instancetype)initAsClientForService: (const char*)serviceName queue: (dispatch_queue_t)queue;
- (instancetype)initAsServerForService: (const char*)serviceName queue: (dispatch_queue_t)queue;
- (instancetype)initWithEndpoint: (XPC_CLASS(endpoint)*)endpoint;
- (instancetype)initAsAnonymousServerWithQueue: (dispatch_queue_t)queue;
// NOTE: this initializer will take ownership of the ports references passed in
// (i.e. the caller loses a reference on both the send port and the receive port)
- (instancetype)initAsServerPeerForServer: (XPC_CLASS(connection)*)server sendPort: (mach_port_t)sendPort receivePort: (mach_port_t)receivePort;

- (void)resume;
- (void)suspend;
- (void)cancel;

/**
 * Takes ownership of the given server peer connection.
 */
- (void)addServerPeer: (XPC_CLASS(connection)*)serverPeer;

/**
 * Disowns the given server peer connection.
 */
- (void)removeServerPeer: (XPC_CLASS(connection)*)serverPeer;

/**
 * Increments the connection's suspension count. Does not actually suspend the connection.
 *
 * @returns `YES` if the connection is now suspended as a result of this call, `NO` otherwise.
 */
- (BOOL)incrementSuspensionCount;

/**
 * Decrements the connection's suspension count. Does not actually resume the connection.
 *
 * @returns `YES` if the connection is now resumed as a result of this call, `NO` otherwise.
 */
- (BOOL)decrementSuspensionCount;

/**
 * Activates the connection, if it has not been activated already.
 *
 * @returns `YES` if the connection was activated as a result of this call, `NO` otherwise.
 */
- (BOOL)activate;

- (void)enqueueSendBarrier: (dispatch_block_t)barrier;

- (void)sendMessage: (XPC_CLASS(dictionary)*)message;
- (void)sendMessage: (XPC_CLASS(dictionary)*)message queue: (dispatch_queue_t)queue withReply: (xpc_handler_t)handler;
- (xpc_object_t)sendMessageWithSynchronousReply: (XPC_CLASS(dictionary)*)message;

- (void)setRemoteCredentials: (audit_token_t*)token;
- (void)copyRemoteCredentials: (audit_token_t*)outToken;

@end

#endif // _XPC_OBJECTS_CONNECTION_H_
