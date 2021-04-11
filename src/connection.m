#import <xpc/objects/connection.h>
#import <xpc/objects/dictionary.h>
#import <xpc/objects/endpoint.h>
#import <xpc/util.h>
#import <xpc/private.h>
#import <xpc/connection.h>
#include <pthread/pthread.h>
#include <bootstrap.h>
#include <xpc/serialization.h>
#import <objc/runtime.h>
#include <Block.h>

XPC_CLASS_SYMBOL_DECL(connection);

XPC_GENARR_DEF(connection, XPC_CLASS(connection)*, /* non-static */);
XPC_GENARR_SEARCH_DEF(connection, XPC_CLASS(connection)*, /* non-static */);
XPC_GENARR_BLOCKS_DEF(connection, XPC_CLASS(connection)*, /* non-static */);

static const char* reason_map[] = {
	"first (invalid)",
	"connected",
	"received",
	"sent",
	"send failed",
	"not sent",
	"barrier completed",
	"disconnected",
	"cancelled",
	"reply received",
	"needs deferred send",
	"sigterm received",
	"async waiter disconnecteed",
	"no senders",
	"last (invalid)",
};

static const char* reason_to_string(dispatch_mach_reason_t reason) {
	if (reason > DISPATCH_MACH_REASON_LAST) {
	return NULL;
	}
	return reason_map[reason];
};

static void server_peer_array_item_dtor(XPC_CLASS(connection)** serverPeer) {
	(*serverPeer).parentServer = nil; // so the server peer doesn't try to remove itself
	[*serverPeer cancel];
	_os_object_release_internal(*serverPeer);
};

static xpc_connection_reply_context_t* xpc_connection_reply_context_create(xpc_handler_t handler, dispatch_queue_t queue) {
	xpc_connection_reply_context_t* context = malloc(sizeof(xpc_connection_reply_context_t));

	if (queue == NULL) {
		queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	}

	context->handler = Block_copy(handler);
	context->queue = [queue retain];

	xpc_log(XPC_LOG_DEBUG, "created reply context %p (with handler %p and queue %p)", context, context->handler, context->queue);

	return context;
};

static void xpc_connection_reply_context_destroy(xpc_connection_reply_context_t* context) {
	xpc_log(XPC_LOG_DEBUG, "destroying reply context %p (with handler %p and queue %p)", context, context->handler, context->queue);
	Block_release(context->handler);
	[context->queue release];
	free(context);
};

// returns `true` if there was no error, `false` otherwise
static bool handle_send_result(dispatch_mach_msg_t message, dispatch_mach_reason_t sendResult, mach_error_t sendError, bool expecting_reply) {
	switch (sendResult) {
		case DISPATCH_MACH_MESSAGE_SENT: {
			xpc_log(XPC_LOG_DEBUG, "message%s successfully sent", expecting_reply ? " expecting reply" : "");
			return true;
		} break;

		case DISPATCH_MACH_NEEDS_DEFERRED_SEND: {
			xpc_log(XPC_LOG_DEBUG, "message%s needs to be sent later", expecting_reply ? " expecting reply" : "");
			return true;
		} break;

		case DISPATCH_MACH_MESSAGE_SEND_FAILED: {
			xpc_log(XPC_LOG_ERROR, "message%s failed to be sent: err = %d", expecting_reply ? " expecting reply" : "", sendError);

			switch (sendError) {
				case MACH_SEND_NO_BUFFER: /* fallthrough */
				case MACH_SEND_INVALID_DATA: /* fallthrough */
				case MACH_SEND_INVALID_HEADER: /* fallthrough */
				case MACH_SEND_INVALID_DEST: /* fallthrough */
				case MACH_SEND_INVALID_NOTIFY: /* fallthrough */
				case MACH_SEND_INVALID_REPLY: /* fallthrough */
				case MACH_SEND_INVALID_TRAILER: {
					// for these, the message wasn't even touched, so we can safely destroy it
					mach_msg_destroy(dispatch_mach_msg_get_msg(message, NULL));
				} break;

				case MACH_SEND_TIMED_OUT:
				case MACH_SEND_INTERRUPTED: {
					// for these, the kernel has completely consumed the message, so we don't need to do anything
				} break;

				case MACH_SEND_INVALID_MEMORY: /* fallthrough */
				case MACH_SEND_INVALID_RIGHT: /* fallthrough */
				case MACH_SEND_INVALID_TYPE: /* fallthrough */
				case MACH_SEND_MSG_TOO_SMALL: {
					// these are hard to clean up because the message may have been partially consumed by the kernel,
					// so we just don't clean them up
					xpc_log(XPC_LOG_WARNING, "message%s could not be cleaned up", expecting_reply ? " expecting reply" : "");
				} break;

				default: {
					xpc_log(XPC_LOG_WARNING, "unexpected error for message%s: %d", expecting_reply ? " expecting reply" : "", sendError);
				} break;
			}
		} break;

		default: {
			xpc_abort("unexpected send result");
		} break;
	}

	return false;
};

static void dispatch_mach_handler(void* context, dispatch_mach_reason_t reason, dispatch_mach_msg_t message, mach_error_t error) {
	XPC_CLASS(connection)* self = context;
	XPC_THIS_DECL(connection);

	xpc_log(XPC_LOG_DEBUG, "connection %p: handler got event %lu (%s)\n", self, reason, reason_to_string(reason));

	switch (reason) {
		case DISPATCH_MACH_MESSAGE_RECEIVED: {
			mach_msg_header_t* header = dispatch_mach_msg_get_msg(message, NULL);

			if (this->is_listener) {
				XPC_CLASS(deserializer)* deserializer = nil;
				mach_port_t sendPort = MACH_PORT_NULL;
				mach_port_t receivePort = MACH_PORT_NULL;
				XPC_CLASS(connection)* serverPeer = nil;

				if (header->msgh_id != XPC_MSGH_ID_CHECKIN) {
					xpc_log(XPC_LOG_NOTICE, "server connection received non-checkin message");
					mach_msg_destroy(header);
					return;
				}

				[message retain]; // because the deserializer consumes a reference on the message
				deserializer = [[[XPC_CLASS(deserializer) alloc] initWithoutHeaderWithMessage: message] autorelease];

				if (![deserializer readPort: &sendPort type: MACH_MSG_TYPE_PORT_SEND]) {
					xpc_abort("failed to read peer send port from checkin message");
				}

				if (![deserializer readPort: &receivePort type: MACH_MSG_TYPE_PORT_RECEIVE]) {
					xpc_abort("failed to read peer receive port from checkin message");
				}

				if (!MACH_PORT_VALID(sendPort) || !MACH_PORT_VALID(receivePort)) {
					xpc_log(XPC_LOG_NOTICE, "peer died before their checkin message went through");
					mach_msg_destroy(header);
					return;
				}

				serverPeer = [[XPC_CLASS(connection) alloc] initAsServerPeerForServer: self sendPort: sendPort receivePort: receivePort];
				[self addServerPeer: serverPeer]; // takes ownership of the server peer connection

				this->event_handler(serverPeer);
			} else {
				XPC_CLASS(dictionary)* dict = nil;

				if (header->msgh_id != XPC_MSGH_ID_MESSAGE) {
					xpc_log(XPC_LOG_NOTICE, "peer connection received non-normal message in normal event handler");
					mach_msg_destroy(header);
					return;
				}

				[message retain]; // because the deserializer consumes a reference on the message
				dict = [XPC_CLASS(deserializer) process: message];
				dict.associatedConnection = self;

				this->event_handler(dict);
			}
		} break;

		case DISPATCH_MACH_CONNECTED: {
			// this event is sent even when we get (re)connected
			xpc_log(XPC_LOG_DEBUG, "connection %p: connected (with send port %u and receive port %u)", self, this->send_port, this->recv_port);
		} break;

		case DISPATCH_MACH_CANCELED: {
			this->is_cancelled = true;
			[self.parentServer removeServerPeer: self]; // server peers should unregister themselves from their parent servers
			xpc_log(XPC_LOG_DEBUG, "connection %p: cancelled", self);
		} break;

		case DISPATCH_MACH_DISCONNECTED: {
			mach_msg_header_t* header = dispatch_mach_msg_get_msg(message, NULL);

			if (MACH_MSGH_BITS_LOCAL(header->msgh_bits) & MACH_MSG_TYPE_MAKE_SEND_ONCE) {
				// we were expecting a reply, so we need to release the reply port
				xpc_mach_port_release_receive(header->msgh_local_port);
			}

			mach_msg_destroy(header);

			if (this->is_cancelled) {
				// we've been cancelled, so this is the very last event we'll ever receive
				// we can release our internal reference
				// note that this doesn't mean we instantly die; the user might still be holding their reference on us
				_os_object_release_internal(self);
			}
		} break;

		case DISPATCH_MACH_REPLY_RECEIVED: {
			mach_msg_header_t* header = dispatch_mach_msg_get_msg(message, NULL);

			xpc_assert(MACH_MSGH_BITS_REMOTE(header->msgh_bits) & MACH_MSG_TYPE_MOVE_SEND_ONCE);
			xpc_mach_port_release_receive(header->msgh_local_port);

			mach_msg_destroy(header);
		} break;

		case DISPATCH_MACH_NO_SENDERS: {
			// servers don't register for no-senders notifications
			xpc_assert(!this->is_listener);

			if (this->is_server_peer || !this->service_name) {
				// server peers and clients of anonymous servers cannot reconnect
				dispatch_mach_cancel(this->mach_ctx);
				this->event_handler(XPC_ERROR_CONNECTION_INVALID);
			} else if (this->service_name) {
				// client of named server
				// we can reconnect
				XPC_CLASS(serializer)* serializer = [[[XPC_CLASS(serializer) alloc] initWithoutHeader] autorelease];
				dispatch_mach_msg_t checkinMessage = NULL;

				// get rid of our old send port and make a new one to send to the server
				xpc_mach_port_release_send(this->send_port);
				this->send_port = xpc_mach_port_create_send_receive();

				if (![serializer writePort: this->send_port type: MACH_MSG_TYPE_MOVE_RECEIVE]) {
					xpc_abort("failed to write server receive port in checkin message");
				}

				if (![serializer writePort: this->recv_port type: MACH_MSG_TYPE_MAKE_SEND]) {
					xpc_abort("failed to write server send port in checkin message");
				}

				checkinMessage = [[[serializer finalizeWithRemotePort: this->checkin_port localPort: MACH_PORT_NULL asReply: NO expectingReply: NO messageID: XPC_MSGH_ID_CHECKIN] retain] autorelease];

				dispatch_mach_reconnect(this->mach_ctx, this->send_port, checkinMessage);

				// let the user know that the connection got wonky
				this->event_handler(XPC_ERROR_CONNECTION_INTERRUPTED);
			}
		} break;

		case DISPATCH_MACH_SIGTERM_RECEIVED: {
			this->event_handler(XPC_ERROR_TERMINATION_IMMINENT);
		} break;

		default: {
			xpc_log(XPC_LOG_NOTICE, "connection %p: received unexpected event %lu (%s)", self, reason, reason_to_string(reason));

			if (message) {
				mach_msg_header_t* header = dispatch_mach_msg_get_msg(message, NULL);
				mach_msg_destroy(header);
			}
		} break;
	}
};

static bool dmxh_direct_message_handler(void* context, dispatch_mach_reason_t reason, dispatch_mach_msg_t message, mach_error_t error) {
	XPC_CLASS(connection)* self = context;

	xpc_log(XPC_LOG_DEBUG, "connection %p: direct message handler got event %lu (%s)\n", self, reason, reason_to_string(reason));

	switch (reason) {
		case DISPATCH_MACH_MESSAGE_SEND_FAILED: /* fallthrough */
		case DISPATCH_MACH_MESSAGE_NOT_SENT: {
			mach_msg_header_t* header = dispatch_mach_msg_get_msg(message, NULL);
			handle_send_result(message, reason, error, MACH_MSGH_BITS_LOCAL(header->msgh_bits) & MACH_MSG_TYPE_MAKE_SEND_ONCE);
			return true;
		} break;

		default:
			return false;
	}
};

static dispatch_queue_t dmxh_msg_context_reply_queue(void* msg_context) {
	xpc_connection_reply_context_t* context = msg_context;
	if (context) {
		return context->queue;
	}
	return NULL;
};

static void dmxh_async_reply_handler(void* self_context, dispatch_mach_reason_t reason, dispatch_mach_msg_t message) {
	XPC_CLASS(connection)* self = self_context;
	XPC_THIS_DECL(connection);
	xpc_connection_reply_context_t* context = dispatch_get_context(message);
	xpc_object_t result = NULL;
	mach_msg_header_t* header = dispatch_mach_msg_get_msg(message, NULL);
	mach_port_t localPort = header->msgh_local_port;

	xpc_log(XPC_LOG_DEBUG, "connection %p: async reply handler got event %lu (%s)\n", self, reason, reason_to_string(reason));

	switch (reason) {
		case DISPATCH_MACH_MESSAGE_RECEIVED: {
			[message retain]; // because the deserializer consumes a reference on the message
			result = [XPC_CLASS(deserializer) process: message];
			if (!result) {
				xpc_abort("failed to deserialize reply");
			}
			// `header` is no longer valid
		} break;

		case DISPATCH_MACH_ASYNC_WAITER_DISCONNECTED: {
			mach_msg_destroy(header);
			if (this->service_name) {
				result = XPC_ERROR_CONNECTION_INTERRUPTED;
			} else {
				result = XPC_ERROR_CONNECTION_INVALID;
			}
		} break;

		default: {
			xpc_abort("unexpected reason received in async reply handler: %lu", reason);
		} break;
	}

	context->handler(result);

	xpc_connection_reply_context_destroy(context);

	xpc_mach_port_release_receive(localPort);
};

static bool dmxh_enable_sigterm_notification(void* context) {
	XPC_CLASS(connection)* self = context;
	XPC_THIS_DECL(connection);
	return this->is_server_peer || this->is_listener;
};

const struct dispatch_mach_xpc_hooks_s dmxh_hooks = {
	.version = DISPATCH_MACH_XPC_HOOKS_VERSION,
	.dmxh_direct_message_handler = dmxh_direct_message_handler,
	.dmxh_msg_context_reply_queue = dmxh_msg_context_reply_queue,
	.dmxh_async_reply_handler = dmxh_async_reply_handler,
	.dmxh_enable_sigterm_notification = dmxh_enable_sigterm_notification,
};

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(connection)

XPC_CLASS_HEADER(connection);
OS_OBJECT_USES_XREF_DISPOSE();

+ (void)installXPCHooks
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		dispatch_mach_hooks_install_4libxpc(&dmxh_hooks);
	});
}

- (void*)userContext
{
	XPC_THIS_DECL(connection);
	return this->user_context;
}

- (void)setUserContext: (void*)userContext
{
	XPC_THIS_DECL(connection);
	this->user_context = userContext;
}

- (const char*)serviceName
{
	XPC_THIS_DECL(connection);
	return this->service_name;
}

- (xpc_handler_t)eventHandler
{
	XPC_THIS_DECL(connection);
	return this->event_handler;
}

- (void)setEventHandler: (xpc_handler_t)eventHandler
{
	XPC_THIS_DECL(connection);
	Block_release(this->event_handler);
	this->event_handler = Block_copy(eventHandler);
}

- (xpc_finalizer_t)finalizer
{
	XPC_THIS_DECL(connection);
	return this->finalizer;
}

- (void)setFinalizer: (xpc_finalizer_t)finalizer
{
	XPC_THIS_DECL(connection);
	this->finalizer = finalizer;
}

- (mach_port_t)sendPort
{
	XPC_THIS_DECL(connection);
	return this->send_port;
}

- (mach_port_t)receivePort
{
	XPC_THIS_DECL(connection);
	return this->recv_port;
}

- (dispatch_queue_t)targetQueue
{
	XPC_THIS_DECL(connection);
	return NULL;
}

- (void)setTargetQueue: (dispatch_queue_t)queue
{
	XPC_THIS_DECL(connection);
	if (this->mach_ctx) {
		dispatch_set_target_queue(this->mach_ctx, queue);
	}
}

- (XPC_CLASS(connection)*)parentServer
{
	XPC_THIS_DECL(connection);
	return objc_loadWeak(&this->parent_server);
}

- (void)setParentServer: (XPC_CLASS(connection)*)parentServer
{
	XPC_THIS_DECL(connection);
	objc_storeWeak(&this->parent_server, parentServer);
}

// _xref_dispose is called when all user references to the object have been released,
// but we're not actually dead yet
- (void)_xref_dispose
{
	XPC_THIS_DECL(connection);

	if (this->is_server_peer) {
		// server peer connections can only be released by the server
		xpc_abort("server peer connection released by user");
	}

	if (this->suspension_count > 0) {
		xpc_abort("last reference to a suspended connection was released");
	}

	if (this->mach_ctx) {
		dispatch_mach_cancel(this->mach_ctx);
	}

	_os_object_release_internal(self);
	// we just released the internal user reference,
	// but we might still be alive until we get fully cancelled and disconnected
	// (if we didn't already)
}

- (void)dealloc
{
	XPC_THIS_DECL(connection);

	pthread_rwlock_destroy(&this->activated_lock);
	pthread_rwlock_destroy(&this->server_peers_lock);

	xpc_mach_port_release_send(this->send_port);
	xpc_mach_port_release_send(this->checkin_port);
	xpc_mach_port_release_receive(this->recv_port);

	[this->mach_ctx release];

	xpc_genarr_connection_destroy(&this->server_peers);

	Block_release(this->event_handler);

	if (this->finalizer) {
		this->finalizer(this->user_context);
	}

	[super dealloc];
}

// not an actual intializer, just a helper
- (void)initCommon: (dispatch_queue_t)targetQueue
{
	XPC_THIS_DECL(connection);

	[[self class] installXPCHooks];

	_os_object_retain_internal(self);

	self.targetQueue = targetQueue;

	pthread_rwlock_init(&this->activated_lock, NULL);
	pthread_rwlock_init(&this->server_peers_lock, NULL);

	this->suspension_count = 1;

	xpc_genarr_connection_init(&this->server_peers, true, server_peer_array_item_dtor);
}

// init helper/common init
- (instancetype)initForService: (const char*)serviceName queue: (dispatch_queue_t)queue asServer: (BOOL)asServer
{
	if (self = [super init]) {
		XPC_THIS_DECL(connection);

		[self initCommon: queue];

		this->is_listener = asServer;
		this->service_name = serviceName;
		this->mach_ctx = dispatch_mach_create_4libxpc((asServer ? "org.darlinghq.libxpc.server" : "org.darlinghq.libxpc.client"), queue, self, dispatch_mach_handler);
	}
	return self;
}

- (instancetype)initAsClientForService: (const char*)serviceName queue: (dispatch_queue_t)queue
{
	if (serviceName == NULL) {
		return [self initAsAnonymousServerWithQueue: queue];
	}
	return [self initForService: serviceName queue: queue asServer: NO];
}

- (instancetype)initAsServerForService: (const char*)serviceName queue: (dispatch_queue_t)queue
{
	return [self initForService: serviceName queue: queue asServer: YES];
}

- (instancetype)initWithEndpoint: (XPC_CLASS(endpoint)*)endpoint
{
	if (self = [super init]) {
		XPC_THIS_DECL(connection);

		[self initCommon: NULL];

		this->mach_ctx = dispatch_mach_create_4libxpc("org.darlinghq.libxpc.endpoint-peer", NULL, self, dispatch_mach_handler);

		if (xpc_mach_port_retain_send(endpoint.port) != KERN_SUCCESS) {
			[self release];
			return nil;
		}
		this->checkin_port = endpoint.port;
	}
	return self;
}

- (instancetype)initAsAnonymousServerWithQueue: (dispatch_queue_t)queue
{
	if (self = [super init]) {
		XPC_THIS_DECL(connection);
		mach_port_t port = xpc_mach_port_create_send_receive();

		[self initCommon: queue];

		if (!MACH_PORT_VALID(port)) {
			[self release];
			return nil;
		}

		this->is_listener = true;
		this->mach_ctx = dispatch_mach_create_4libxpc("org.darlinghq.libxpc.anonymous-server", queue, self, dispatch_mach_handler);

		this->send_port = port;
		this->recv_port = port;
	}
	return self;
}

- (instancetype)initAsServerPeerForServer: (XPC_CLASS(connection)*)server sendPort: (mach_port_t)sendPort receivePort: (mach_port_t)receivePort
{
	if (self = [super init]) {
		XPC_THIS_DECL(connection);

		[self initCommon: NULL];

		self.parentServer = server;

		this->is_server_peer = true;
		this->mach_ctx = dispatch_mach_create_4libxpc("org.darlinghq.libxpc.server-peer", NULL, self, dispatch_mach_handler);

		this->send_port = sendPort;
		this->recv_port = receivePort;
	}
	return self;
}

- (void)addServerPeer: (XPC_CLASS(connection)*)serverPeer
{
	XPC_THIS_DECL(connection);
	pthread_rwlock_wrlock(&this->server_peers_lock);
	xpc_genarr_connection_append(&this->server_peers, &serverPeer);
	pthread_rwlock_unlock(&this->server_peers_lock);
}

- (void)removeServerPeer: (XPC_CLASS(connection)*)serverPeer
{
	XPC_THIS_DECL(connection);
	size_t index = SIZE_MAX;

	pthread_rwlock_wrlock(&this->server_peers_lock);
	index = xpc_genarr_connection_find(&this->server_peers, &serverPeer);
	if (index != SIZE_MAX) {
		xpc_genarr_connection_remove(&this->server_peers, index);
	}
	pthread_rwlock_unlock(&this->server_peers_lock);
}

// assumes proper locking is performed and it is being called without contention
- (void)activateLocked
{
	XPC_THIS_DECL(connection);
	kern_return_t status = KERN_SUCCESS;
	dispatch_mach_msg_t checkinMessage = NULL;
	mach_port_t checkinPort = MACH_PORT_NULL;

	if (this->is_listener && this->service_name) {
		// named server
		status = bootstrap_check_in(bootstrap_port, this->service_name, &this->recv_port);
		if (status != KERN_SUCCESS) {
			goto error_out;
		}
	} else if (this->is_listener) {
		// anonymous server
		// should already have ports set up
		xpc_assert(MACH_PORT_VALID(this->send_port));
		xpc_assert(MACH_PORT_VALID(this->recv_port));
	} else if (this->service_name) {
		// client for named server
		status = bootstrap_look_up(bootstrap_port, this->service_name, &this->checkin_port);
		if (status != KERN_SUCCESS) {
			goto error_out;
		}
	} else if (this->is_server_peer) {
		// server peer
		// should already have ports set up
		xpc_assert(MACH_PORT_VALID(this->send_port));
		xpc_assert(MACH_PORT_VALID(this->recv_port));
	} else {
		// client for anonymous server
		// should already have a checkin port
		xpc_assert(MACH_PORT_VALID(this->checkin_port));
	}

	// if we have a checkin port, we need to checkin
	if (MACH_PORT_VALID(this->checkin_port)) {
		XPC_CLASS(serializer)* serializer = [[[XPC_CLASS(serializer) alloc] initWithoutHeader] autorelease];

		// okay, i have to admit, i usually say "wtf" when i learn how Apple implements certain things,
		// but for this one, i gotta hand it to them, it's actually pretty smart:
		// clients pass in a receive port and a send port in their checkin message,
		// which the server then uses to create a dedicated peer connection.

		this->send_port = xpc_mach_port_create_send_receive();
		this->recv_port = xpc_mach_port_create_receive();

		// we give the server the receive right and keep the send right
		if (![serializer writePort: this->send_port type: MACH_MSG_TYPE_MOVE_RECEIVE]) {
			xpc_abort("failed to write server receive port in checkin message");
		}

		// we give the server a send right and keep the receive right
		if (![serializer writePort: this->recv_port type: MACH_MSG_TYPE_MAKE_SEND]) {
			xpc_abort("failed to write server send port in checkin message");
		}

		checkinMessage = [[[serializer finalizeWithRemotePort: this->checkin_port localPort: MACH_PORT_NULL asReply: NO expectingReply: NO messageID: XPC_MSGH_ID_CHECKIN] retain] autorelease];
	}

	if (!this->is_listener) {
		// * clients (of both kinds) want to know when their server peers die
		// * server peers want to know when their client peers die
		dispatch_mach_request_no_senders(this->mach_ctx);
	}

	dispatch_mach_connect(this->mach_ctx, this->recv_port, this->send_port, checkinMessage);

out:
	this->activated = true;
	return;

error_out:
	xpc_mach_port_release_send(this->send_port);
	xpc_mach_port_release_receive(this->recv_port);
	this->activated = false;
}

- (BOOL)activate
{
	XPC_THIS_DECL(connection);

	// read the value first
	pthread_rwlock_rdlock(&this->activated_lock);
	BOOL activated = this->activated;
	pthread_rwlock_unlock(&this->activated_lock);

	if (activated) {
		// we've already been activated
		return NO;
	}

	// otherwise, we might need to activate ourselves
	// acquire the lock for writing
	pthread_rwlock_wrlock(&this->activated_lock);

	// make sure we're still not activated
	// someone else might have tried to acquire the lock for writing at the same time as us
	if (!(activated = this->activated)) {
		// ok, now we're the only one activating
		[self activateLocked];
	}

	pthread_rwlock_unlock(&this->activated_lock);

	return !activated;
}

- (BOOL)incrementSuspensionCount
{
	XPC_THIS_DECL(connection);
	intmax_t old = atomic_fetch_add_explicit(&this->suspension_count, 1, memory_order_relaxed);
	if (old < 0) {
		xpc_abort("connection was resumed too many times");
	}
	// if the suspension count was 0, it is now 1 (so we are suspended)
	return old == 0;
}

- (BOOL)decrementSuspensionCount
{
	XPC_THIS_DECL(connection);
	intmax_t old = atomic_fetch_sub_explicit(&this->suspension_count, 1, memory_order_relaxed);
	if (old <= 0) {
		xpc_abort("connection was resumed too many times");
	}
	// if the suspension count was 1, it is now 0 (so we are not suspended)
	return old == 1;
}

- (void)resume
{
	XPC_THIS_DECL(connection);

	if (![self decrementSuspensionCount]) {
		// still suspended
		return;
	}

	if (![self activate]) {
		return dispatch_resume(this->mach_ctx);
	}
}

- (void)suspend
{
	XPC_THIS_DECL(connection);

	if (![self incrementSuspensionCount]) {
		// we were already suspended
		return;
	}

	dispatch_suspend(this->mach_ctx);
}

- (void)cancel
{
	XPC_THIS_DECL(connection);
	this->suspension_count = 0;
	dispatch_mach_cancel(this->mach_ctx);
}

- (void)enqueueSendBarrier: (dispatch_block_t)barrier
{
	XPC_THIS_DECL(connection);
	dispatch_mach_send_barrier(this->mach_ctx, barrier);
}

- (void)sendMessage: (XPC_CLASS(dictionary)*)contents
{
	@autoreleasepool {
		XPC_THIS_DECL(connection);
		XPC_CLASS(serializer)* serializer = [XPC_CLASS(serializer) serializer];
		dispatch_mach_msg_t message = NULL;
		dispatch_mach_reason_t sendResult = 0;
		mach_error_t sendError = ERR_SUCCESS;

		if (![serializer writeObject: contents]) {
			xpc_abort("failed to serialize dictionary");
		}

		message = [serializer finalizeWithRemotePort: MACH_PORT_VALID(contents.outgoingPort) ? contents.outgoingPort : this->send_port
		                                   localPort: MACH_PORT_NULL
		                                     asReply: contents.isReply
		                              expectingReply: NO];
		if (!message) {
			xpc_abort("failed to finalize message");
		}

		dispatch_mach_send_with_result(this->mach_ctx, message, 0, 0, &sendResult, &sendError);

		handle_send_result(message, sendResult, sendError, false);
	}
}

- (void)sendMessage: (XPC_CLASS(dictionary)*)contents queue: (dispatch_queue_t)queue withReply: (xpc_handler_t)handler
{
	@autoreleasepool {
		XPC_THIS_DECL(connection);
		XPC_CLASS(serializer)* serializer = [XPC_CLASS(serializer) serializer];
		xpc_connection_reply_context_t* context = NULL;
		dispatch_mach_msg_t message = NULL;
		mach_port_t replyPort = xpc_mach_port_create_receive();
		dispatch_mach_reason_t sendResult = 0;
		mach_error_t sendError = ERR_SUCCESS;

		if (!MACH_PORT_VALID(replyPort)) {
			xpc_abort("failed to allocate reply port");
		}

		if (![serializer writeObject: contents]) {
			xpc_abort("failed to serialize dictionary");
		}

		message = [serializer finalizeWithRemotePort: MACH_PORT_VALID(contents.outgoingPort) ? contents.outgoingPort : this->send_port
		                                   localPort: replyPort
		                                     asReply: contents.isReply
		                              expectingReply: YES];
		if (!message) {
			xpc_abort("failed to finalize message");
		}

		context = xpc_connection_reply_context_create(handler, queue);
		dispatch_set_context(message, context);

		dispatch_mach_send_with_result_and_async_reply_4libxpc(this->mach_ctx, message, 0, 0, &sendResult, &sendError);

		handle_send_result(message, sendResult, sendError, true);
		// no need to call the user handler or destroy the context on error
		// libdispatch will always call async reply handler, with either success or failure
	}
}

- (xpc_object_t)sendMessageWithSynchronousReply: (XPC_CLASS(dictionary)*)contents
{
	XPC_THIS_DECL(connection);
	dispatch_mach_msg_t reply = NULL;
	XPC_CLASS(dictionary)* result = nil;

	@autoreleasepool {
		XPC_CLASS(serializer)* serializer = [XPC_CLASS(serializer) serializer];
		dispatch_mach_msg_t message = NULL;
		dispatch_mach_reason_t sendResult = 0;
		mach_error_t sendError = ERR_SUCCESS;

		if (![serializer writeObject: contents]) {
			xpc_abort("failed to serialize dictionary");
		}

		message = [serializer finalizeWithRemotePort: MACH_PORT_VALID(contents.outgoingPort) ? contents.outgoingPort : this->send_port
		                                   localPort: MACH_PORT_NULL // let the channel manage the reply port
		                                     asReply: contents.isReply
		                              expectingReply: YES];
		if (!message) {
			xpc_abort("failed to finalize message");
		}

		reply = dispatch_mach_send_with_result_and_wait_for_reply(this->mach_ctx, message, 0, 0, &sendResult, &sendError);

		handle_send_result(message, sendResult, sendError, true);
	}

	if (!reply) {
		if (this->service_name) {
			return XPC_ERROR_CONNECTION_INTERRUPTED;
		} else {
			return XPC_ERROR_CONNECTION_INVALID;
		}
	}

	@autoreleasepool {
		// give it its own autoreleasepool to reduce memory usage
		// (to ensure that the serializer from before is released)
		result = [[XPC_CLASS(deserializer) process: reply] retain];
	}

	return result;
}

@end

//
// C API
//

XPC_EXPORT
xpc_connection_t xpc_connection_create(const char* name, dispatch_queue_t targetq) {
	return [[XPC_CLASS(connection) alloc] initAsClientForService: name queue: targetq];
};

XPC_EXPORT
xpc_connection_t xpc_connection_create_mach_service(const char* name, dispatch_queue_t targetq, uint64_t flags) {
	if (flags & XPC_CONNECTION_MACH_SERVICE_LISTENER) {
		return xpc_connection_create_listener(name, targetq);
	} else {
		return [[XPC_CLASS(connection) alloc] initAsClientForService: name queue: targetq];
	}
};

XPC_EXPORT
xpc_connection_t xpc_connection_create_from_endpoint(xpc_endpoint_t xendpoint) {
	TO_OBJC_CHECKED(endpoint, xendpoint, endpoint) {
		return [[XPC_CLASS(connection) alloc] initWithEndpoint: endpoint];
	}
	return NULL;
};

XPC_EXPORT
void xpc_connection_set_target_queue(xpc_connection_t xconn, dispatch_queue_t targetq) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		conn.targetQueue = targetq;
	}
};

XPC_EXPORT
void xpc_connection_set_event_handler(xpc_connection_t xconn, xpc_handler_t handler) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		conn.eventHandler = handler;
	}
};

XPC_EXPORT
void xpc_connection_suspend(xpc_connection_t xconn) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		return [conn suspend];
	}
};

XPC_EXPORT
void xpc_connection_resume(xpc_connection_t xconn) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		return [conn resume];
	}
};

XPC_EXPORT
void xpc_connection_send_message(xpc_connection_t xconn, xpc_object_t xmsg) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		TO_OBJC_CHECKED(dictionary, xmsg, msg) {
			return [conn sendMessage: msg];
		}
	}
};

XPC_EXPORT
void xpc_connection_send_barrier(xpc_connection_t xconn, dispatch_block_t barrier) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		return [conn enqueueSendBarrier: barrier];
	}
};

XPC_EXPORT
void xpc_connection_send_message_with_reply(xpc_connection_t xconn, xpc_object_t xmsg, dispatch_queue_t replyq, xpc_handler_t handler) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		TO_OBJC_CHECKED(dictionary, xmsg, msg) {
			return [conn sendMessage: msg queue: replyq withReply: handler];
		}
	}
};

XPC_EXPORT
xpc_object_t xpc_connection_send_message_with_reply_sync(xpc_connection_t xconn, xpc_object_t xmsg) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		TO_OBJC_CHECKED(dictionary, xmsg, msg) {
			return [conn sendMessageWithSynchronousReply: msg];
		}
	}
	return NULL;
};

XPC_EXPORT
void xpc_connection_cancel(xpc_connection_t xconn) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		return [conn cancel];
	}
};

XPC_EXPORT
const char* xpc_connection_get_name(xpc_connection_t xconn) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		return conn.serviceName;
	}
	return NULL;
};

XPC_EXPORT
uid_t xpc_connection_get_euid(xpc_connection_t xconn) {
	xpc_stub();
	return UID_MAX;
};

XPC_EXPORT
gid_t xpc_connection_get_egid(xpc_connection_t xconn) {
	xpc_stub();
	return GID_MAX;
};

XPC_EXPORT
pid_t xpc_connection_get_pid(xpc_connection_t xconn) {
	xpc_stub();
	return -1;
};

XPC_EXPORT
au_asid_t xpc_connection_get_asid(xpc_connection_t xconn) {
	xpc_stub();
	return AU_ASSIGN_ASID;
};

XPC_EXPORT
void xpc_connection_set_context(xpc_connection_t xconn, void* context) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		conn.userContext = context;
	}
};

XPC_EXPORT
void* xpc_connection_get_context(xpc_connection_t xconn) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		return conn.userContext;
	}
	return NULL;
};

XPC_EXPORT
void xpc_connection_set_finalizer_f(xpc_connection_t xconn, xpc_finalizer_t finalizer) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		conn.finalizer = finalizer;
	}
};

XPC_EXPORT
void xpc_connection_set_legacy(xpc_connection_t xconn) {
	xpc_stub();
};

XPC_EXPORT
void xpc_connection_set_privileged(xpc_connection_t xconn) {
	xpc_stub();
};

XPC_EXPORT
void xpc_connection_activate(xpc_connection_t xconn) {
	TO_OBJC_CHECKED(connection, xconn, conn) {
		if ([conn activate]) {
			[conn decrementSuspensionCount];
		}
	}
};

XPC_EXPORT
void xpc_connection_set_target_uid(xpc_connection_t xconn, uid_t uid) {
	xpc_stub();
};

XPC_EXPORT
void xpc_connection_set_instance(xpc_connection_t xconn, uuid_t uuid) {
	xpc_stub();
};

XPC_EXPORT
xpc_object_t xpc_connection_copy_entitlement_value(xpc_connection_t xconn, const char* entitlement) {
	xpc_stub();
	return NULL;
};

//
// private C API
//

XPC_EXPORT
void _xpc_connection_set_event_handler_f(xpc_connection_t xconn, void (*handler)(xpc_object_t event, void* context)) {
	// unsure about the parameters to the handler
	// maybe the second parameter to the handler is actually the connection object?
	xpc_stub();
};

XPC_EXPORT
char* xpc_connection_copy_bundle_id(xpc_connection_t xconn) {
	// returns a string that must be freed
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_connection_t xpc_connection_create_listener(const char* name, dispatch_queue_t queue) {
	return [[XPC_CLASS(connection) alloc] initAsServerForService: name queue: queue];
};

XPC_EXPORT
void xpc_connection_enable_sim2host_4sim(xpc_connection_t xconn) {
	xpc_stub();
};

XPC_EXPORT
void xpc_connection_enable_termination_imminent_event(xpc_connection_t xconn) {
	xpc_stub();
};

XPC_EXPORT
void xpc_connection_get_audit_token(xpc_connection_t xconn, audit_token_t* out_token) {
	xpc_stub();
};

XPC_EXPORT
uint8_t xpc_connection_get_bs_type(xpc_connection_t xconn) {
	xpc_stub();
	return 0;
};

XPC_EXPORT
void xpc_connection_get_instance(xpc_connection_t xconn, uint8_t* out_uuid) {
	xpc_stub();
};

XPC_EXPORT
bool xpc_connection_is_extension(xpc_connection_t xconn) {
	return false;
};

XPC_EXPORT
void xpc_connection_kill(xpc_connection_t xconn, int signal) {
	xpc_stub();
};

XPC_EXPORT

void xpc_connection_send_notification(xpc_connection_t xconn, xpc_object_t details) {
	xpc_stub();
};

XPC_EXPORT
void xpc_connection_set_bootstrap(xpc_connection_t xconn, xpc_object_t bootstrap) {
	xpc_stub();
};

XPC_EXPORT
void xpc_connection_set_bs_type(xpc_connection_t xconn, uint8_t type) {
	xpc_stub();
};

XPC_EXPORT
void xpc_connection_set_event_channel(xpc_connection_t xconn, const char* channel_name) {
	// parameter 2 is a guess
	xpc_stub();
};

XPC_EXPORT
void xpc_connection_set_non_launching(xpc_connection_t xconn, bool non_launching) {
	xpc_stub();
};

XPC_EXPORT
void xpc_connection_set_oneshot_instance(xpc_connection_t xconn, const uint8_t* uuid) {
	xpc_stub();
};

XPC_EXPORT
void xpc_connection_set_qos_class_fallback(xpc_connection_t xconn, dispatch_qos_class_t qos_class) {
	xpc_stub();
};

XPC_EXPORT
void xpc_connection_set_qos_class_floor(xpc_connection_t xconn, dispatch_qos_class_t qos_class, int relative_priority) {
	xpc_stub();
};