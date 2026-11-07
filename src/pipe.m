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

#import <xpc/objects/pipe.h>
#import <xpc/objects/dictionary.h>
#import <xpc/xpc.h>
#import <xpc/private.h>
#import <xpc/util.h>
#import <xpc/serialization.h>

#include <bootstrap_priv.h>
#include <errno.h>

#define DEFAULT_RECEIVE_SIZE 256

XPC_LOGGER_DEF(pipe);

//
// implementation notes:
//
// Pipes share the exact same communication protocol as connections, including the checkin requirement,
// but implement a simpler, more synchronously-oriented API.
//
// From Apple's current pipe API, it seems that they can only be used as a client interface, not a server interface.
// There are, however, certain functions in the C API that are essentially class methods (i.e. they don't take a pipe instance as an argument)
// and most of these seem to be oriented for server use.
//
// One interesting "instance method" that stands out in contrast with the connection API is `xpc_pipe_routine_forward`.
// This function allows a service to act as a proxy, and any replies from the handling service are sent directly to the original client.
//

XPC_CLASS_SYMBOL_DECL(pipe);

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(pipe)

XPC_CLASS_HEADER(pipe);

- (void)dealloc
{
	XPC_THIS_DECL(pipe);

	pthread_rwlock_destroy(&this->state_lock);

	xpc_mach_port_release_send(this->checkin_port);
	xpc_mach_port_release_send(this->send_port);
	xpc_mach_port_release_receive(this->recv_port);

	[super dealloc];
}

+ (int)handleMachMessageSendReturnCode: (mach_msg_return_t)ret withMessageHeader: (mach_msg_header_t*)header
{
	int status = 0;

	switch (ret) {
		case MACH_SEND_NO_BUFFER: /* fallthrough */
		case MACH_SEND_INVALID_DATA: /* fallthrough */
		case MACH_SEND_INVALID_HEADER: /* fallthrough */
		case MACH_SEND_INVALID_NOTIFY: /* fallthrough */
		case MACH_SEND_INVALID_REPLY: /* fallthrough */
		case MACH_SEND_INVALID_TRAILER: {
			// for these, the message wasn't even touched, so we can safely destroy it
			mach_msg_destroy(header);

			status = EIO;
		} break;

		case MACH_SEND_INVALID_DEST: {
			mach_msg_destroy(header);

			status = EPIPE;
		} break;

		case MACH_SEND_TIMED_OUT:
		case MACH_SEND_INTERRUPTED: {
			// for these, the kernel has completely consumed the message, so we don't need to do anything

			status = EIO;
		} break;

		case MACH_SEND_INVALID_MEMORY: /* fallthrough */
		case MACH_SEND_INVALID_RIGHT: /* fallthrough */
		case MACH_SEND_INVALID_TYPE: /* fallthrough */
		case MACH_SEND_MSG_TOO_SMALL: {
			// these are hard to clean up because the message may have been partially consumed by the kernel,
			// so we just don't clean them up
			xpc_log_error(pipe, "pipe: message could not be cleaned up");

			status = EIO;
		} break;

		case MACH_MSG_SUCCESS: {
			status = 0;
		} break;
	}

	return status;
}

+ (int)handleMachMessageReceiveReturnCode: (mach_msg_return_t)ret
{
	int status = 0;

	switch (ret) {
		case MACH_RCV_INVALID_NAME: /* fallthrough */
		case MACH_RCV_IN_SET: /* fallthrough */
		case MACH_RCV_TIMED_OUT: /* fallthrough */
		case MACH_RCV_INTERRUPTED: /* fallthrough */
		case MACH_RCV_PORT_DIED: /* fallthrough */
		case MACH_RCV_PORT_CHANGED: {
			// nothing happened to the message

			status = EIO;
		} break;

		case MACH_RCV_HEADER_ERROR: /* fallthrough */
		case MACH_RCV_INVALID_NOTIFY: {
			// message was dequeued and destroyed

			status = EIO;
		} break;

		case MACH_RCV_TOO_LARGE: {
			status = EAGAIN;
		} break;

		case MACH_RCV_BODY_ERROR: /* fallthrough */
		case MACH_RCV_INVALID_DATA: {
			// message was received

			status = EIO;
		} break;

		case MACH_MSG_SUCCESS: {
			status = 0;
		} break;
	}

	return status;
}

+ (int)receiveMachMessageWithPort: (mach_port_t)port incomingMessage: (dispatch_mach_msg_t*)incomingMessage flags: (uint64_t)flags
{
	int status = 0;
	dispatch_mach_msg_t message = NULL;
	size_t messageSize = DEFAULT_RECEIVE_SIZE + MAX_TRAILER_SIZE;
	mach_msg_header_t* header = NULL;
	mach_msg_return_t ret = MACH_MSG_SUCCESS;

retry:
	if (message != NULL) { [message release]; }
	message = dispatch_mach_msg_create(NULL, messageSize, DISPATCH_MACH_MSG_DESTRUCTOR_DEFAULT, &header);
	if (!message) {
		status = ENOMEM;
		goto out;
	}

	ret = mach_msg(header, MACH_RCV_MSG | MACH_RCV_LARGE | MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) | MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT), 0, messageSize, port, 0, MACH_PORT_NULL);

	status = [[self class] handleMachMessageReceiveReturnCode: ret];

	if (status == EAGAIN) {
		messageSize = header->msgh_size + MAX_TRAILER_SIZE;
		goto retry;
	} else if (status == 0) {
		*incomingMessage = [message retain];
	}

out:
	[message release];
	return status;
}

+ (int)receiveWithPort: (mach_port_t)port incomingMessage: (xpc_object_t*)incomingMessage flags: (uint64_t)flags
{
	int status = 0;
	dispatch_mach_msg_t message = NULL;
	mach_msg_header_t* header = NULL;
	mach_msg_return_t ret = MACH_MSG_SUCCESS;

	status = [[self class] receiveMachMessageWithPort: port incomingMessage: &message flags: flags];

	if (status == 0) {
		header = dispatch_mach_msg_get_msg(message, NULL);

		if (header->msgh_id == XPC_MSGH_ID_MESSAGE || header->msgh_id == XPC_MSGH_ID_ASYNC_REPLY) {
			XPC_CLASS(dictionary)* dict = nil;

			dict = [XPC_CLASS(deserializer) process: [message retain]];
			if (!dict) {
				status = EIO;
				goto out;
			}

			[dict setAssociatedAuditToken: xpc_mach_msg_audit_token(header)];

			// The deserializer autoreleases its result. The C pipe API
			// transfers an owned reference to the caller.
			*incomingMessage = [dict retain];

			status = 0;
		} else {
			xpc_log_fault(pipe, "pipe: received invalid message with ID: %u", header->msgh_id);

			mach_msg_destroy(header);

			status = EIO;
			goto out;
		}
	}

out:
	[message release];
	return status;
}

+ (int)tryReceiveWithPort: (mach_port_t)port incomingMessage: (xpc_object_t*)incomingMessage replyPort: (mach_port_t*)replyPort maximumMIGReplySize: (size_t)maximumMIGReplySize flags:(uint64_t)flags demuxer:(xpc_pipe_mig_demux_f)demuxer
{
	int status = 0;
	dispatch_mach_msg_t message = NULL;
	dispatch_mach_msg_t reply = NULL;
	mach_msg_header_t* header = NULL;
	mach_msg_header_t* replyHeader = NULL;

	status = [[self class] receiveMachMessageWithPort: port incomingMessage: &message flags: flags];

	if (status == 0) {
		header = dispatch_mach_msg_get_msg(message, NULL);

		if (header->msgh_id == XPC_MSGH_ID_MESSAGE || header->msgh_id == XPC_MSGH_ID_ASYNC_REPLY) {
			XPC_CLASS(dictionary)* dict = nil;

			dict = [XPC_CLASS(deserializer) process: [message retain]];
			if (!dict) {
				status = EIO;
				goto out;
			}

			// The receiver identifies the sender by this token
			// (`xpc_dictionary_get_audit_token`), like for a message received
			// on a connection.
			[dict setAssociatedAuditToken: xpc_mach_msg_audit_token(header)];

			*incomingMessage = [dict retain];
			*replyPort = header->msgh_local_port;

			status = 0;
		} else {
			replyHeader = NULL;
			reply = dispatch_mach_msg_create(NULL, maximumMIGReplySize, DISPATCH_MACH_MSG_DESTRUCTOR_DEFAULT, &replyHeader);

			status = [[self class] demux: header reply: replyHeader demuxer: demuxer];
		}
	}

out:
	[message release];
	[reply release];
	return status;
}

+ (int)sendReply: (XPC_CLASS(dictionary)*)contents
{
	int status = 0;
	XPC_CLASS(serializer)* serializer = nil;
	dispatch_mach_msg_t message = NULL;
	mach_msg_header_t* header = NULL;
	size_t messageSize = 0;
	mach_msg_return_t ret = MACH_MSG_SUCCESS;

	if (!contents.isReply) {
		status = EINVAL;
		goto out;
	}

	serializer = [XPC_CLASS(serializer) new];
	if (!serializer) {
		status = ENOMEM;
		goto out;
	}

	if (![serializer writeObject: contents]) {
		status = EINVAL;
		goto out;
	}

	message = [serializer finalizeWithRemotePort: contents.outgoingPort
	                                   localPort: MACH_PORT_NULL
	                                     asReply: YES
	                              expectingReply: NO];
	if (!message) {
		// could either be invalid arguments or insufficient memory,
		// but at this point, insufficient memory is more likely
		status = ENOMEM;
		goto out;
	}

	message = [message retain];
	header = dispatch_mach_msg_get_msg(message, &messageSize);
	[serializer release];
	serializer = nil;

	ret = mach_msg(header, MACH_SEND_MSG, messageSize, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);

	status = [[self class] handleMachMessageSendReturnCode: ret withMessageHeader: header];

out:
	[serializer release];
	[message release];
	return status;
}

+ (int)demux: (mach_msg_header_t*)request reply: (mach_msg_header_t*)reply demuxer: (xpc_pipe_mig_demux_f)demuxer
{
	// refer to `dispatch_mach_mig_demux` to see why this method does what it does

	int status = 0;
	mig_reply_error_t* replyContent = (mig_reply_error_t*)reply;

	if (!demuxer(request, reply)) {
		mach_msg_destroy(reply);

		status = EINVAL;
		goto out;
	}

	switch (replyContent->RetCode) {
		case KERN_SUCCESS: {
			// everything's good
		} break;

		case MIG_NO_REPLY: {
			// not really an error, just indicates that we should not reply
			replyContent->Head.msgh_remote_port = MACH_PORT_NULL;
		} break;

		default: {
			// quoting a comment in `dispatch_mach_mig_demux`:
			// > destroy the request - but not the reply port
			// > (MIG moved it into the bufReply).
			request->msgh_remote_port = MACH_PORT_NULL;
			mach_msg_destroy(request);
		} break;
	}

	if (MACH_PORT_VALID(replyContent->Head.msgh_remote_port)) {
		mach_msg_return_t ret = mach_msg(reply, MACH_SEND_MSG, reply->msgh_size, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);

		status = [[self class] handleMachMessageSendReturnCode: ret withMessageHeader: reply];

		if (status == EPIPE) {
			// peer died; not a big deal
			status = 0;
		}
	}

out:
	return status;
}

- (BOOL)broken
{
	XPC_THIS_DECL(pipe);
	BOOL broken = YES;
	pthread_rwlock_rdlock(&this->state_lock);
	broken = this->state == xpc_pipe_state_broken;
	pthread_rwlock_unlock(&this->state_lock);
	return broken;
}

- (void)setBroken: (BOOL)broken
{
	XPC_THIS_DECL(pipe);
	if (!broken) {
		return;
	}
	pthread_rwlock_wrlock(&this->state_lock);
	this->state = xpc_pipe_state_broken;
	pthread_rwlock_unlock(&this->state_lock);
}

- (instancetype)initForService: (const char*)serviceName withFlags: (uint64_t)flags
{
	mach_port_t servicePort = MACH_PORT_NULL;

	if (bootstrap_look_up2(bootstrap_port, serviceName, &servicePort, 0, (flags & XPC_PIPE_FLAG_PRIVILEGED) ? BOOTSTRAP_PRIVILEGED_SERVER : 0) != BOOTSTRAP_SUCCESS) {
		self = [super init];
		[self release];
		return nil;
	}

	self = [self initWithPort: servicePort flags: flags];

	xpc_mach_port_release_send(servicePort);

	return self;
}

- (instancetype)initWithPort: (mach_port_t)port flags: (uint64_t)flags
{
	if (self = [super init]) {
		XPC_THIS_DECL(pipe);

		pthread_rwlock_init(&this->state_lock, NULL);

		if (xpc_mach_port_retain_send(port) != KERN_SUCCESS) {
			[self release];
			return nil;
		}

		this->checkin_port = port;

		if (MACH_PORT_VALID(port) && port == bootstrap_port) {
			// launchd is not an XPC listener: it receives pipe routines
			// directly on the bootstrap port (`xpc_pipe_try_receive` on its
			// port set) and never sees a checkin, so messages go straight to
			// the port.
			if (xpc_mach_port_retain_send(port) != KERN_SUCCESS) {
				[self release];
				return nil;
			}
			this->send_port = port;
			this->recv_port = MACH_PORT_NULL;
			this->state = xpc_pipe_state_active;
			return self;
		}

		this->send_port = xpc_mach_port_create_send_receive();
		this->recv_port = xpc_mach_port_create_receive();

		if (!MACH_PORT_VALID(this->checkin_port) || !MACH_PORT_VALID(this->send_port) || !MACH_PORT_VALID(this->recv_port)) {
			[self release];
			return nil;
		}
	}
	return self;
}

- (int)activateLocked
{
	XPC_THIS_DECL(pipe);
	XPC_CLASS(serializer)* serializer = [[XPC_CLASS(serializer) alloc] initWithoutHeader];
	dispatch_mach_msg_t message = NULL;
	mach_msg_header_t* header = NULL;
	kern_return_t ret = KERN_SUCCESS;
	size_t messageSize = 0;

	if (![serializer writePort: this->send_port type: MACH_MSG_TYPE_MOVE_RECEIVE]) {
		goto error_out;
	}

	// we don't actually use this receive port, but the server needs it
	if (![serializer writePort: this->recv_port type: MACH_MSG_TYPE_MAKE_SEND]) {
		goto error_out;
	}

	message = [serializer finalizeWithRemotePort: this->checkin_port localPort: MACH_PORT_NULL asReply: NO expectingReply: NO messageID: XPC_MSGH_ID_CHECKIN];
	if (!message) {
		goto error_out;
	}

	header = dispatch_mach_msg_get_msg(message, &messageSize);
	if (!header) {
		goto error_out;
	}

	ret = mach_msg(header, MACH_SEND_MSG, messageSize, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
	if (ret != KERN_SUCCESS) {
		goto error_out;
	}

	// we're now active
	this->state = xpc_pipe_state_active;
	[serializer release];
	return 0;

error_out:
	// if we failed to checkin, this pipe is now useless
	this->state = xpc_pipe_state_broken;
	[serializer release];
	return EPIPE;
}

- (int)activate
{
	XPC_THIS_DECL(pipe);
	xpc_pipe_state_t state = xpc_pipe_state_broken;

	// first, try the fast-path (i.e. we've already been activated)
	pthread_rwlock_rdlock(&this->state_lock);
	state = this->state;
	pthread_rwlock_unlock(&this->state_lock);

	// if we're not currently in the initial state,
	// we're either active (which is what we want) or we're broken (which we can't do anything about),
	// in either case, all we can do is return.
	if (state != xpc_pipe_state_initial) {
		goto out;
	}

	pthread_rwlock_wrlock(&this->state_lock);
	// make sure nobody activated us or broke us while we had the lock dropped
	if ((state = this->state) == xpc_pipe_state_initial) {
		[self activateLocked];
		state = this->state;
	}
	pthread_rwlock_unlock(&this->state_lock);

out:
	if (state == xpc_pipe_state_active) {
		return 0;
	} else {
		return EPIPE;
	}
}

- (int)sendMessage: (XPC_CLASS(dictionary)*)contents withSynchronousReply: (xpc_object_t*)reply flags: (uint64_t)flags
{
	XPC_THIS_DECL(pipe);
	int status = 0;
	mach_port_t replyPort = MACH_PORT_NULL;
	XPC_CLASS(serializer)* serializer = nil;
	dispatch_mach_msg_t message = NULL;
	mach_msg_header_t* header = NULL;
	size_t messageSize = 0;
	BOOL sent = NO;
	mach_msg_return_t ret = MACH_MSG_SUCCESS;

	status = [self activate];
	if (status != 0) {
		goto out;
	}

	replyPort = mig_get_reply_port();
	if (!MACH_PORT_VALID(replyPort)) {
		status = ENOMEM;
		goto out;
	}

	serializer = [XPC_CLASS(serializer) new];
	if (!serializer) {
		status = ENOMEM;
		goto out;
	}

	if (![serializer writeObject: contents]) {
		status = EINVAL;
		goto out;
	}

	message = [serializer finalizeWithRemotePort: MACH_PORT_VALID(contents.outgoingPort) ? contents.outgoingPort : this->send_port
	                                   localPort: replyPort
	                                     asReply: contents.isReply
	                              expectingReply: YES];
	if (!message) {
		// could either be invalid arguments or insufficient memory,
		// but at this point, insufficient memory is more likely
		status = ENOMEM;
		goto out;
	}

	message = [message retain];
	header = dispatch_mach_msg_get_msg(message, &messageSize);
	[serializer release];
	serializer = nil;

retry:
	// do the send and receive at the same time as an optimization
	ret = mach_msg(header, (sent ? 0 : MACH_SEND_MSG) | MACH_RCV_MSG | MACH_RCV_LARGE | MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) | MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT), sent ? 0 : messageSize, messageSize, replyPort, 0, MACH_PORT_NULL);
	sent = YES;

	status = [[self class] handleMachMessageSendReturnCode: ret withMessageHeader: header];

	if (status == 0) {
		status = [[self class] handleMachMessageReceiveReturnCode: ret];

		if (status == EAGAIN) {
			messageSize = header->msgh_size + MAX_TRAILER_SIZE;
			[message release];
			message = dispatch_mach_msg_create(NULL, messageSize, DISPATCH_MACH_MSG_DESTRUCTOR_DEFAULT, &header);
			goto retry;
		} else if (status == 0) {
			if (header->msgh_id == XPC_MSGH_ID_ASYNC_REPLY) {
				XPC_CLASS(dictionary)* dict = nil;

				dict = [XPC_CLASS(deserializer) process: [message retain]];
				if (!dict) {
					status = EIO;
					goto out;
				}

				*reply = [dict retain];

				status = 0;
			} else {
				xpc_log_error(pipe, "pipe: received invalid reply message with ID: %u", header->msgh_id);

				mach_msg_destroy(header);

				status = EIO;
				goto out;
			}
		}
	}

out:
	if (status == EPIPE) {
		self.broken = YES;
	}
	[serializer release];
	[message release];
	return status;
}

- (int)sendMessage: (XPC_CLASS(dictionary)*)contents withReplyPort: (mach_port_t)replyPort
{
	XPC_THIS_DECL(pipe);
	int status = 0;
	XPC_CLASS(serializer)* serializer = nil;
	dispatch_mach_msg_t message = NULL;
	mach_msg_header_t* header = NULL;
	size_t messageSize = 0;
	mach_msg_return_t ret = MACH_MSG_SUCCESS;

	status = [self activate];
	if (status != 0) {
		goto out;
	}

	serializer = [XPC_CLASS(serializer) new];
	if (!serializer) {
		status = ENOMEM;
		goto out;
	}

	if (![serializer writeObject: contents]) {
		status = EINVAL;
		goto out;
	}

	message = [serializer finalizeWithRemotePort: MACH_PORT_VALID(contents.outgoingPort) ? contents.outgoingPort : this->send_port
	                                   localPort: replyPort
	                                     asReply: contents.isReply
	                              expectingReply: YES];
	if (!message) {
		// could either be invalid arguments or insufficient memory,
		// but at this point, insufficient memory is more likely
		status = ENOMEM;
		goto out;
	}

	message = [message retain];
	header = dispatch_mach_msg_get_msg(message, &messageSize);
	[serializer release];
	serializer = nil;

	ret = mach_msg(header, MACH_SEND_MSG, messageSize, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);

	status = [[self class] handleMachMessageSendReturnCode: ret withMessageHeader: header];

out:
	if (status == EPIPE) {
		self.broken = YES;
	}
	[serializer release];
	[message release];
	return status;
}

- (int)forwardMessage: (XPC_CLASS(dictionary)*)contents
{
	XPC_THIS_DECL(pipe);
	int status = 0;
	XPC_CLASS(serializer)* serializer = nil;
	dispatch_mach_msg_t message = NULL;
	mach_msg_header_t* header = NULL;
	size_t messageSize = 0;
	mach_msg_return_t ret = MACH_MSG_SUCCESS;
	bool forwardedMessageExpectsReply = contents.expectsReply;

	status = [self activate];
	if (status != 0) {
		goto out;
	}

	serializer = [XPC_CLASS(serializer) new];
	if (!serializer) {
		status = ENOMEM;
		goto out;
	}

	if (![serializer writeObject: contents]) {
		status = EINVAL;
		goto out;
	}

	message = [serializer finalizeWithRemotePort: this->send_port
	                                   localPort: contents.incomingPort
	                                     asReply: NO
	                              expectingReply: forwardedMessageExpectsReply];
	if (!message) {
		// could either be invalid arguments or insufficient memory,
		// but at this point, insufficient memory is more likely
		status = ENOMEM;
		goto out;
	}

	message = [message retain];
	header = dispatch_mach_msg_get_msg(message, &messageSize);
	[serializer release];
	serializer = nil;

	header->msgh_local_port = contents.incomingPort;
	header->msgh_bits = (header->msgh_bits & ~MACH_MSGH_BITS_LOCAL_MASK) | ((forwardedMessageExpectsReply ? MACH_MSG_TYPE_MOVE_SEND_ONCE : MACH_MSG_TYPE_COPY_SEND) << 8);

	contents.incomingPort = MACH_PORT_NULL;

	ret = mach_msg(header, MACH_SEND_MSG, messageSize, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);

	status = [[self class] handleMachMessageSendReturnCode: ret withMessageHeader: header];

out:
	if (status == EPIPE) {
		self.broken = YES;
	}
	[serializer release];
	[message release];
	return status;
}

- (int)sendMessage: (XPC_CLASS(dictionary)*)contents
{
	XPC_THIS_DECL(pipe);
	int status = 0;
	XPC_CLASS(serializer)* serializer = nil;
	dispatch_mach_msg_t message = NULL;
	mach_msg_header_t* header = NULL;
	size_t messageSize = 0;
	mach_msg_return_t ret = MACH_MSG_SUCCESS;

	status = [self activate];
	if (status != 0) {
		goto out;
	}

	serializer = [XPC_CLASS(serializer) new];
	if (!serializer) {
		status = ENOMEM;
		goto out;
	}

	if (![serializer writeObject: contents]) {
		status = EINVAL;
		goto out;
	}

	message = [serializer finalizeWithRemotePort: MACH_PORT_VALID(contents.outgoingPort) ? contents.outgoingPort : this->send_port
	                                   localPort: MACH_PORT_NULL
	                                     asReply: contents.isReply
	                              expectingReply: NO];
	if (!message) {
		// could either be invalid arguments or insufficient memory,
		// but at this point, insufficient memory is more likely
		status = ENOMEM;
		goto out;
	}

	message = [message retain];
	header = dispatch_mach_msg_get_msg(message, &messageSize);
	[serializer release];
	serializer = nil;

	ret = mach_msg(header, MACH_SEND_MSG, messageSize, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);

	status = [[self class] handleMachMessageSendReturnCode: ret withMessageHeader: header];

out:
	if (status == EPIPE) {
		self.broken = YES;
	}
	[serializer release];
	[message release];
	return status;
}

- (void)invalidate
{
	XPC_THIS_DECL(pipe);

	self.broken = YES;

	xpc_mach_port_release_send(this->checkin_port);
	this->checkin_port = MACH_PORT_NULL;

	xpc_mach_port_release_send(this->send_port);
	this->send_port = MACH_PORT_NULL;

	xpc_mach_port_release_receive(this->recv_port);
	this->recv_port = MACH_PORT_NULL;
}

@end

//
// private C API
//

XPC_EXPORT
void xpc_pipe_invalidate(xpc_pipe_t xpipe) {
	TO_OBJC_CHECKED(pipe, xpipe, pipe) {
		return [pipe invalidate];
	}
};

XPC_EXPORT
xpc_pipe_t xpc_pipe_create(const char* name, uint64_t flags) {
	return [[XPC_CLASS(pipe) alloc] initForService: name withFlags: flags];
};

XPC_EXPORT
xpc_pipe_t xpc_pipe_create_from_port(mach_port_t port, uint64_t flags) {
	return [[XPC_CLASS(pipe) alloc] initWithPort: port flags: flags];
};

XPC_EXPORT
int xpc_pipe_routine_reply(xpc_object_t xdict) {
	TO_OBJC_CHECKED(dictionary, xdict, dict) {
		return [XPC_CLASS(pipe) sendReply: dict];
	}

	return EINVAL;
};

XPC_EXPORT
int xpc_pipe_routine(xpc_pipe_t xpipe, xpc_object_t xdict, xpc_object_t* reply) {
	// The deserializer autoreleases the reply and the pipe methods retain it for the caller (+1), so the
	// autoreleased references must be drained here: launchd's loop has no pool of its own, and objc4
	// would create one that never drains.
	@autoreleasepool {
		TO_OBJC_CHECKED(pipe, xpipe, pipe) {
			TO_OBJC_CHECKED(dictionary, xdict, dict) {
				return [pipe sendMessage: dict withSynchronousReply: reply flags: 0];
			}
		}
	}

	return EINVAL;
};

XPC_EXPORT
int xpc_pipe_try_receive(mach_port_t port, xpc_object_t* out_object, mach_port_t* out_local_port, boolean_t (*demuxer)(mach_msg_header_t* request, mach_msg_header_t* reply), mach_msg_size_t max_mig_reply_size, uint64_t flags) {
	int r;
	// See xpc_pipe_routine: the received message is returned owned, everything autoreleased is drained here.
	@autoreleasepool {
		r = [XPC_CLASS(pipe) tryReceiveWithPort: port incomingMessage: out_object replyPort: out_local_port maximumMIGReplySize: max_mig_reply_size flags: flags demuxer: demuxer];
	}
	return r;
};

XPC_EXPORT
int _xpc_pipe_handle_mig(mach_msg_header_t* request, mach_msg_header_t* reply, boolean_t (*demuxer)(mach_msg_header_t* request, mach_msg_header_t* reply)) {
	return [XPC_CLASS(pipe) demux: request reply: reply demuxer: demuxer];
};

XPC_EXPORT
int xpc_pipe_receive(mach_port_t receive_port, xpc_object_t* out_msg, uint64_t flags) {
	// See xpc_pipe_routine: the received message is returned owned, everything autoreleased is drained here.
	@autoreleasepool {
		return [XPC_CLASS(pipe) receiveWithPort: receive_port incomingMessage: out_msg flags: flags];
	}
};

XPC_EXPORT
int xpc_pipe_routine_async(xpc_pipe_t xpipe, xpc_object_t xdict, mach_port_t local_reply_port) {
	TO_OBJC_CHECKED(pipe, xpipe, pipe) {
		TO_OBJC_CHECKED(dictionary, xdict, dict) {
			return [pipe sendMessage: dict withReplyPort: local_reply_port];
		}
	}

	return EINVAL;
};

XPC_EXPORT
int xpc_pipe_routine_forward(xpc_pipe_t xpipe, xpc_object_t xdict) {
	TO_OBJC_CHECKED(pipe, xpipe, pipe) {
		TO_OBJC_CHECKED(dictionary, xdict, dict) {
			return [pipe forwardMessage: dict];
		}
	}

	return EINVAL;
};

XPC_EXPORT
int xpc_pipe_routine_with_flags(xpc_pipe_t xpipe, xpc_object_t xdict, xpc_object_t* reply, uint64_t flags) {
	// See xpc_pipe_routine.
	@autoreleasepool {
		TO_OBJC_CHECKED(pipe, xpipe, pipe) {
			TO_OBJC_CHECKED(dictionary, xdict, dict) {
				return [pipe sendMessage: dict withSynchronousReply: reply flags: flags];
			}
		}
	}

	return EINVAL;
};

XPC_EXPORT
int xpc_pipe_simpleroutine(xpc_pipe_t xpipe, xpc_object_t xdict) {
	TO_OBJC_CHECKED(pipe, xpipe, pipe) {
		TO_OBJC_CHECKED(dictionary, xdict, dict) {
			return [pipe sendMessage: dict];
		}
	}

	return EINVAL;
};
