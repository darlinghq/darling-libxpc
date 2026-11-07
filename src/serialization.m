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

#include <xpc/serialization.h>
#include <xpc/internal.h>
#include <xpc/activity.h>
#include <mach/mach_vm.h>

// maximum number of ports of the same type to embed in an inline descriptor.
// if the number of ports of the same type exceeds this number, they are all stuffed into an OOL descriptor.
#define OOL_PORT_THRESHOLD 1

// the type symbols (XPC_TYPE_*), indexed by serialized type
static const void* const xpc_classes[] = {
	XPC_TYPE_NULL,
	XPC_TYPE_BOOL,
	XPC_TYPE_INT64,
	XPC_TYPE_UINT64,
	XPC_TYPE_DOUBLE,
	XPC_TYPE_POINTER,
	XPC_TYPE_DATE,
	XPC_TYPE_DATA,
	XPC_TYPE_STRING,
	XPC_TYPE_UUID,
	XPC_TYPE_FD,
	XPC_TYPE_SHMEM,
	XPC_TYPE_MACH_SEND,
	XPC_TYPE_ARRAY,
	XPC_TYPE_DICTIONARY,
	XPC_TYPE_ERROR,
	XPC_TYPE_CONNECTION,
	XPC_TYPE_ENDPOINT,
	XPC_TYPE_SERIALIZER,
	XPC_TYPE_PIPE,
	XPC_TYPE_MACH_RECV,
	XPC_TYPE_BUNDLE,
	XPC_TYPE_SERVICE,
	XPC_TYPE_SERVICE_INSTANCE,
	XPC_TYPE_ACTIVITY,
	XPC_TYPE_FILE_TRANSFER,
};

XPC_INLINE
Class type_to_class(uint32_t type) {
	if ((type & 0xfff) != 0 || type < XPC_SERIAL_TYPE_MIN || type > XPC_SERIAL_TYPE_MAX) {
		return nil;
	}
	return XPC_CLASS_FOR_TYPE(xpc_classes[(type / 0x1000) - 1]);
};

XPC_INLINE
uint32_t class_to_type(Class class) {
	const void* type = XPC_TYPE_FOR_CLASS(class);
	for (size_t i = 0; i < (sizeof(xpc_classes) / sizeof(*xpc_classes)); ++i) {
		if (xpc_classes[i] == type) {
			return (i + 1) * 0x1000;
		}
	}
	return XPC_SERIAL_TYPE_INVALID;
};

static size_t descriptor_sizes[] = {
	sizeof(mach_msg_port_descriptor_t),
	sizeof(mach_msg_ool_descriptor_t),
	sizeof(mach_msg_ool_ports_descriptor_t),
	sizeof(mach_msg_ool_ports_descriptor_t),
	sizeof(mach_msg_guarded_port_descriptor_t),
};

XPC_INLINE
size_t descriptor_size(mach_msg_descriptor_type_t type) {
	if (type > sizeof(descriptor_sizes) / sizeof(*descriptor_sizes)) {
		return 0;
	}
	return descriptor_sizes[type];
};

XPC_CLASS_SYMBOL_DECL(serializer);
XPC_CLASS_SYMBOL_DECL(deserializer);

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(serializer)

XPC_CLASS_HEADER(serializer);

- (NSUInteger)offset
{
	XPC_THIS_DECL(serializer);
	return this->offset;
}

- (BOOL)isFinalized
{
	XPC_THIS_DECL(serializer);
	return this->finalized_message != NULL;
}

- (void)dealloc
{
	XPC_THIS_DECL(serializer);

	if (this->finalized_message != NULL) {
		dispatch_release(this->finalized_message);
	}

	if (this->buffer != NULL) {
		free(this->buffer);
	}

	for (size_t i = 0; i < sizeof(this->port_arrays) / sizeof(*this->port_arrays); ++i) {
		mach_port_right_t port_right = xpc_mach_msg_type_name_to_port_right(i + MACH_MSG_SEND_DISPOSITION_FIRST);
		xpc_serial_port_array_t* port_array = &this->port_arrays[i];
		if (port_array->array != NULL) {
			for (size_t j = 0; j < port_array->length; ++j) {
				xpc_mach_port_release_right(port_array->array[j], port_right);
			}
			free(port_array->array);
			port_array->array = NULL;
			port_array->length = 0;
		}
	}

	[super dealloc];
}

- (instancetype)init
{
	if (self = [self initWithoutHeader]) {
		XPC_THIS_DECL(serializer);

		if (![self ensure: sizeof(xpc_serial_header_t)]) {
			[self release];
			return nil;
		}

		if (![self writeU32: XPC_SERIAL_MAGIC]) {
			[self release];
			return nil;
		}

		if (![self writeU32: XPC_SERIAL_CURRENT_VERSION]) {
			[self release];
			return nil;
		}
	}
	return self;
}

- (instancetype)initWithoutHeader
{
	if (self = [super init]) {
		// nothing
	}
	return self;
}

- (dispatch_mach_msg_t)finalizeWithRemotePort: (mach_port_t)remotePort localPort: (mach_port_t)localPort asReply: (BOOL)asReply expectingReply: (BOOL)expectingReply messageID: (uint32_t)messageID
{
	XPC_THIS_DECL(serializer);
	size_t messageSize = sizeof(mach_msg_header_t);
	mach_msg_base_t* base = NULL;
	mach_msg_descriptor_t* descriptors = NULL;
	void* body = NULL;
	size_t descriptorCount = 0;

	if (this->finalized_message) {
		return this->finalized_message;
	}

	// first, determine the total message size

	// add in port descriptor sizes
	for (size_t i = 0; i < sizeof(this->port_arrays) / sizeof(*this->port_arrays); ++i) {
		xpc_serial_port_array_t* port_array = &this->port_arrays[i];
		if (port_array->length > OOL_PORT_THRESHOLD) {
			// for anything more than the OOL threshold, we use an OOL port array
			messageSize += sizeof(mach_msg_ool_ports_descriptor_t);
			++descriptorCount;
		} else if (port_array->length > 0) {
			// otherwise, we use an inline descriptor for each
			messageSize += port_array->length * sizeof(mach_msg_port_descriptor_t);
			descriptorCount += port_array->length;
		}
	}

	// if we have ports, the message must be complex so we need the complex body
	if (descriptorCount > 0) {
		messageSize += sizeof(mach_msg_body_t);
	}

	// add in the length of the actual serialized XPC data
	messageSize += this->length;

	// now we allocate the message
	this->finalized_message = dispatch_mach_msg_create(NULL, messageSize, DISPATCH_MACH_MSG_DESTRUCTOR_DEFAULT, (mach_msg_header_t**)&base);
	if (!this->finalized_message) {
		return NULL;
	}
	descriptors = (mach_msg_descriptor_t*)((char*)base + sizeof(*base));

	// if we have no descriptors, we don't need to include the count
	body = (descriptorCount > 0) ? (void*)descriptors : (void*)((char*)base + sizeof(base->header));

	// next, fill in header information
	base->header.msgh_id = messageID;
	base->header.msgh_size = messageSize;
	base->header.msgh_bits = MACH_MSGH_BITS(asReply ? MACH_MSG_TYPE_MOVE_SEND_ONCE : MACH_MSG_TYPE_COPY_SEND, expectingReply ? MACH_MSG_TYPE_MAKE_SEND_ONCE : 0) | ((descriptorCount > 0) ? MACH_MSGH_BITS_COMPLEX : 0);
	base->header.msgh_remote_port = remotePort;
	base->header.msgh_local_port = expectingReply ? localPort : MACH_PORT_NULL;

	if (descriptorCount > 0) {
		base->body.msgh_descriptor_count = descriptorCount;
	}

	// and transfer the port descriptors
	for (size_t i = 0; i < sizeof(this->port_arrays) / sizeof(*this->port_arrays); ++i) {
		xpc_serial_port_array_t* port_array = &this->port_arrays[i];
		mach_msg_type_name_t disposition = i + MACH_MSG_SEND_DISPOSITION_FIRST;

		if (port_array->length > OOL_PORT_THRESHOLD) {
			mach_msg_ool_ports_descriptor_t* ool_ports_desc = body;
			body = (char*)body + sizeof(*ool_ports_desc);

			ool_ports_desc->type = MACH_MSG_OOL_PORTS_DESCRIPTOR;
			ool_ports_desc->disposition = disposition;
			ool_ports_desc->copy = MACH_MSG_VIRTUAL_COPY;
			ool_ports_desc->deallocate = 1;
			ool_ports_desc->count = port_array->length;
			ool_ports_desc->address = NULL;

			// it might be wasteful to be allocating whole pages just for a few mach_port_t's,
			// but it's the best way to ensure the array survives until the kernel receives it (and the kernel will take care of deallocating it)
			if (mach_vm_allocate(mach_task_self(), (mach_vm_address_t*)&ool_ports_desc->address, sizeof(mach_port_t) * port_array->length, VM_FLAGS_ANYWHERE) != KERN_SUCCESS) {
				xpc_abort("failed to allocate memory for OOL port array");
			}

			memcpy(ool_ports_desc->address, port_array->array, sizeof(mach_port_t) * port_array->length);
		} else if (port_array->length > 0) {
			for (size_t j = 0; j < port_array->length; ++j) {
				mach_msg_port_descriptor_t* port_desc = body;
				body = (char*)body + sizeof(*port_desc);

				port_desc->type = MACH_MSG_PORT_DESCRIPTOR;
				port_desc->disposition = disposition;
				port_desc->name = port_array->array[j];
			}
		}

		// we've transferred ownership of the ports in this array into the message,
		// so we can release the array now (and that way our destructor won't try to release them)
		if (port_array->length > 0) {
			free(port_array->array);
			port_array->array = NULL;
			port_array->length = 0;
		}
	}

	// finally, copy in the serialized XPC data...
	memcpy(body, this->buffer, this->length);

	// ...and free our buffer
	free(this->buffer);
	this->buffer = NULL;

	return this->finalized_message;
}

- (dispatch_mach_msg_t)finalizeWithRemotePort: (mach_port_t)remotePort localPort: (mach_port_t)localPort asReply: (BOOL)asReply expectingReply: (BOOL)expectingReply
{
	return [self finalizeWithRemotePort: remotePort localPort: localPort asReply: asReply expectingReply: expectingReply messageID: asReply ? XPC_MSGH_ID_ASYNC_REPLY : XPC_MSGH_ID_MESSAGE];
}

- (BOOL)needsToResizeToWrite: (NSUInteger)extraSize
{
	XPC_THIS_DECL(serializer);
	return extraSize > this->length - this->offset;
}

- (BOOL)ensure: (NSUInteger)extraSize
{
	XPC_THIS_DECL(serializer);
	if ([self needsToResizeToWrite: extraSize]) {
		size_t extra = extraSize - (this->length - this->offset);
		void* newBuffer = realloc(this->buffer, this->length + extra);
		if (this->length + extra > 0 && newBuffer == NULL) {
			return NO;
		}
		this->buffer = newBuffer;
		this->length += extra;
	}
	return YES;
}

- (BOOL)write: (const void*)data length: (NSUInteger)length
{
	XPC_THIS_DECL(serializer);
	size_t total_length = xpc_serial_padded_length(length);
	size_t padding_length = total_length - length;

	if (![self ensure: total_length]) {
		return NO;
	}

	if (data != NULL) {
		memcpy(&this->buffer[this->offset], data, length);
	}
	this->offset += length;
	memset(&this->buffer[this->offset], 0, padding_length);
	this->offset += padding_length;

	return YES;
}

- (BOOL)reserve: (NSUInteger)length region: (void**)region
{
	XPC_THIS_DECL(serializer);
	if (region != NULL) {
		*region = &this->buffer[this->offset];
	}
	return [self write: NULL length: length];
}

- (BOOL)writeString: (const char*)string
{
	return [self write: string length: strlen(string) + 1];
}

- (BOOL)writeU32: (uint32_t)value
{
	char data[sizeof(uint32_t)];
	OSWriteLittleInt32(data, 0, value);
	return [self write: data length: sizeof(data)];
}

- (BOOL)writeU64: (uint64_t)value
{
	char data[sizeof(uint64_t)];
	OSWriteLittleInt64(data, 0, value);
	return [self write: data length: sizeof(data)];
}

- (BOOL)writePort: (mach_port_t)port type: (mach_msg_type_name_t)type
{
	XPC_THIS_DECL(serializer);
	xpc_serial_port_array_t* port_array = NULL;
	mach_port_t* expanded_array = NULL;

	if (!MACH_MSG_TYPE_PORT_ANY(type)) {
		return NO;
	}

	port_array = &this->port_arrays[type - MACH_MSG_SEND_DISPOSITION_FIRST];

	expanded_array = realloc(port_array->array, (port_array->length + 1) * sizeof(mach_port_t));
	if (!expanded_array) {
		return NO;
	}
	port_array->array = expanded_array;

	port_array->array[port_array->length++] = port;

	return YES;
}

- (BOOL)writeObject: (XPC_CLASS(object)*)object
{
	XPC_THIS_DECL(serializer);
	size_t savedOffset = this->offset;
	uint32_t type = class_to_type([object class]);
	if (type == XPC_SERIAL_TYPE_INVALID) {
		goto error_out;
	}
	if (![self ensure: object.serializationLength]) {
		goto error_out;
	}
	if (![object serialize: self]) {
		goto error_out;
	}

	return YES;

error_out:
	this->offset = savedOffset;
	return NO;
}

+ (instancetype)serializer
{
	return [[[self class] new] autorelease];
}

@end

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(deserializer)

XPC_CLASS_HEADER(deserializer);

- (NSUInteger)offset
{
	XPC_THIS_DECL(deserializer);
	return this->offset;
}

- (mach_port_t)remotePort
{
	XPC_THIS_DECL(deserializer);
	mach_msg_header_t* header = dispatch_mach_msg_get_msg(this->mach_msg, NULL);
	return header->msgh_remote_port;
}

- (void)dealloc
{
	XPC_THIS_DECL(deserializer);

	if (this->mach_msg != NULL) {
		dispatch_release(this->mach_msg);
	}

	// release any ports that weren't consumed, plus the arrays themselves
	for (size_t i = 0; i < sizeof(this->port_arrays) / sizeof(*this->port_arrays); ++i) {
		mach_port_right_t port_right = xpc_mach_msg_type_name_to_port_right(i + MACH_MSG_RECV_DISPOSITION_FIRST);
		xpc_deserial_port_array_t* port_array = &this->port_arrays[i];
		if (port_array->array != NULL) {
			for (size_t j = port_array->offset; j < port_array->length; ++j) {
				xpc_mach_port_release_right(port_array->array[j], port_right);
			}
			free(port_array->array);
			port_array->array = NULL;
		}
	}

	[super dealloc];
}

- (instancetype)initWithMessage: (dispatch_mach_msg_t)message
{
	if (self = [self initWithoutHeaderWithMessage: message]) {
		uint32_t magic = 0;
		uint32_t version = 0;

		// make sure this is an XPC message
		if (![self readU32: &magic]) {
			[self release];
			return nil;
		}
		if (magic != XPC_SERIAL_MAGIC) {
			[self release];
			return nil;
		}

		if (![self readU32: &version]) {
			[self release];
			return nil;
		}
		if (version != XPC_SERIAL_CURRENT_VERSION) {
			[self release];
			return nil;
		}
	}
	return self;
}

- (instancetype)initWithoutHeaderWithMessage: (dispatch_mach_msg_t)message
{
	if (self = [super init]) {
		XPC_THIS_DECL(deserializer);
		size_t messageSize = 0;
		const mach_msg_base_t* base = (const mach_msg_base_t*)dispatch_mach_msg_get_msg(message, &messageSize);
		const mach_msg_descriptor_t* descriptors = (const mach_msg_descriptor_t*)((const char*)base + sizeof(mach_msg_base_t));

		// if it's not complex, it doesn't contain a descriptor count; the XPC data comes immediately after the header
		const void* body = MACH_MSGH_BITS_IS_COMPLEX(base->header.msgh_bits) ? (const void*)descriptors : (const void*)((const char*)base + sizeof(base->header));

		// don't retain it; we own it now
		this->mach_msg = message;

		if (MACH_MSGH_BITS_IS_COMPLEX(base->header.msgh_bits)) {
			// first, count how many ports we have of each
			for (size_t i = 0; i < base->body.msgh_descriptor_count; ++i) {
				const mach_msg_descriptor_t* descriptor = body;
				body = (const char*)body + descriptor_size(descriptor->type.type);

				switch (descriptor->type.type) {
					case MACH_MSG_PORT_DESCRIPTOR: {
						const mach_msg_port_descriptor_t* port_desc = (const mach_msg_port_descriptor_t*)descriptor;
						if (!MACH_MSG_TYPE_PORT_ANY_RIGHT(port_desc->disposition)) {
							xpc_abort("unexpected port disposition in Mach message");
						}
						++this->port_arrays[port_desc->disposition - MACH_MSG_RECV_DISPOSITION_FIRST].length;
					} break;
					case MACH_MSG_OOL_PORTS_DESCRIPTOR: {
						const mach_msg_ool_ports_descriptor_t* ool_ports_desc = (const mach_msg_ool_ports_descriptor_t*)descriptor;
						if (!MACH_MSG_TYPE_PORT_ANY_RIGHT(ool_ports_desc->disposition)) {
							xpc_abort("unexpected OOL port disposition in Mach message");
						}
						this->port_arrays[ool_ports_desc->disposition - MACH_MSG_RECV_DISPOSITION_FIRST].length += ool_ports_desc->count;
					} break;
					case MACH_MSG_GUARDED_PORT_DESCRIPTOR: {
						// treat it like a normal port; we'll unguard it later
						const mach_msg_guarded_port_descriptor_t* guarded_desc = (const mach_msg_guarded_port_descriptor_t*)descriptor;
						if (!MACH_MSG_TYPE_PORT_ANY_RIGHT(guarded_desc->disposition)) {
							xpc_abort("unexpected port disposition in Mach message");
						}
						++this->port_arrays[guarded_desc->disposition - MACH_MSG_RECV_DISPOSITION_FIRST].length;
					} break;
				}
			}

			// next, let's allocate arrays to store the ports
			for (size_t i = 0; i < sizeof(this->port_arrays) / sizeof(*this->port_arrays); ++i) {
				this->port_arrays[i].array = calloc(this->port_arrays[i].length, sizeof(mach_port_t));
				if (this->port_arrays[i].length > 0 && this->port_arrays[i].array == NULL) {
					xpc_abort("failed to allocate memory for port arrays");
				}
			}

			// now we actually save the ports and deallocate memory passed in for OOL descriptors
			body = descriptors;
			for (size_t i = 0; i < base->body.msgh_descriptor_count; ++i) {
				const mach_msg_descriptor_t* descriptor = body;
				body = (const char*)body + descriptor_size(descriptor->type.type);

				switch (descriptor->type.type) {
					case MACH_MSG_PORT_DESCRIPTOR: {
						const mach_msg_port_descriptor_t* port_desc = (const mach_msg_port_descriptor_t*)descriptor;
						xpc_deserial_port_array_t* port_array = &this->port_arrays[port_desc->disposition - MACH_MSG_RECV_DISPOSITION_FIRST];
						port_array->array[port_array->offset++] = port_desc->name;
					} break;

					case MACH_MSG_OOL_PORTS_DESCRIPTOR: {
						const mach_msg_ool_ports_descriptor_t* ool_ports_desc = (const mach_msg_ool_ports_descriptor_t*)descriptor;
						xpc_deserial_port_array_t* port_array = &this->port_arrays[ool_ports_desc->disposition - MACH_MSG_RECV_DISPOSITION_FIRST];

						memcpy(&port_array->array[port_array->offset], ool_ports_desc->address, ool_ports_desc->count * sizeof(mach_port_t));
						port_array->offset += ool_ports_desc->count;

						if (ool_ports_desc->deallocate) {
							vm_deallocate(mach_task_self(), (vm_address_t)ool_ports_desc->address, ool_ports_desc->count * sizeof(mach_port_t));
						}
					} break;

					case MACH_MSG_GUARDED_PORT_DESCRIPTOR: {
						const mach_msg_guarded_port_descriptor_t* guarded_desc = (const mach_msg_guarded_port_descriptor_t*)descriptor;
						xpc_deserial_port_array_t* port_array = &this->port_arrays[guarded_desc->disposition - MACH_MSG_RECV_DISPOSITION_FIRST];

						// we should never have to deal with guarded ports, but if we ever do,
						// we should unguard them so they can be used like other ports
						if ((guarded_desc->flags & MACH_MSG_GUARD_FLAGS_UNGUARDED_ON_SEND) == 0) {
							mach_port_unguard(mach_task_self(), guarded_desc->name, guarded_desc->context);
						}

						port_array->array[port_array->offset++] = guarded_desc->name;
					} break;

					// we don't use these, but we have to deallocate them if we ever encountered them.
					// we should probably log a warning or something if we find these
					case MACH_MSG_OOL_DESCRIPTOR:
					case MACH_MSG_OOL_VOLATILE_DESCRIPTOR: {
						const mach_msg_ool_descriptor_t* ool_desc = (const mach_msg_ool_descriptor_t*)descriptor;
						if (ool_desc->deallocate) {
							vm_deallocate(mach_task_self(), (vm_address_t)ool_desc->address, ool_desc->size);
						}
					} break;
				}
			}

			// reset the port array offsets
			for (size_t i = 0; i < sizeof(this->port_arrays) / sizeof(*this->port_arrays); ++i) {
				this->port_arrays[i].offset = 0;
			}
		}

		// the `body` pointer now points to the actual serialized XPC data
		this->buffer = body;
		this->length = messageSize - ((uintptr_t)body - (uintptr_t)base);
	}
	return self;
}

- (BOOL)ensure: (NSUInteger)extraSize
{
	XPC_THIS_DECL(deserializer);
	return extraSize <= this->length - this->offset;
}

- (BOOL)read: (void*)data length: (NSUInteger)length
{
	XPC_THIS_DECL(deserializer);
	size_t total_length = xpc_serial_padded_length(length);

	if (![self ensure: total_length]) {
		return NO;
	}

	if (data != NULL) {
		memcpy(data, &this->buffer[this->offset], length);
	}
	this->offset += total_length;
	return YES;
}

- (BOOL)consume: (NSUInteger)length region: (const void**)region
{
	XPC_THIS_DECL(deserializer);
	if (region != NULL) {
		*region = &this->buffer[this->offset];
	}
	return [self read: NULL length: length];
}

- (BOOL)readString: (const char**)string
{
	XPC_THIS_DECL(deserializer);
	return [self consume: strlen(&this->buffer[this->offset]) + 1 region: (const void**)string];
}

- (BOOL)readU32: (uint32_t*)value
{
	const void* data = NULL;
	if (![self consume: sizeof(uint32_t) region: &data]) {
		return NO;
	}
	if (value != NULL) {
		*value = OSReadLittleInt32(data, 0);
	}
	return YES;
}

- (BOOL)readU64: (uint64_t*)value
{
	const void* data = NULL;
	if (![self consume: sizeof(uint64_t) region: &data]) {
		return NO;
	}
	if (value != NULL) {
		*value = OSReadLittleInt64(data, 0);
	}
	return YES;
}

- (BOOL)readPort: (mach_port_t*)port type: (mach_msg_type_name_t)type
{
	XPC_THIS_DECL(deserializer);
	xpc_deserial_port_array_t* port_array = NULL;

	if (!MACH_MSG_TYPE_PORT_ANY_RIGHT(type)) {
		return NO;
	}

	port_array = &this->port_arrays[type - MACH_MSG_RECV_DISPOSITION_FIRST];

	if (port_array->offset >= port_array->length) {
		return NO;
	}

	if (port == NULL) {
		// just release the right
		xpc_mach_port_release_right(port_array->array[port_array->offset], xpc_mach_msg_type_name_to_port_right(type));
	} else {
		// the caller now owns the right
		*port = port_array->array[port_array->offset];
	}

	port_array->array[port_array->offset++] = MACH_PORT_NULL;

	return YES;
}

- (BOOL)readObject: (XPC_CLASS(object)**)object
{
	XPC_THIS_DECL(deserializer);
	size_t savedOffset = this->offset;
	uint32_t type = XPC_SERIAL_TYPE_INVALID;
	Class class = nil;
	XPC_CLASS(object)* result = nil;

	if (![self peekU32: &type]) {
		goto error_out;
	}

	class = type_to_class(type);
	if (class == nil) {
		goto error_out;
	}

	result = [class deserialize: self];
	if (result == nil) {
		goto error_out;
	}

	if (object != NULL) {
		*object = result;
	}

	return YES;

error_out:
	this->offset = savedOffset;
	return NO;
}

- (BOOL)peek: (void*)data length: (NSUInteger)length
{
	XPC_THIS_DECL(deserializer);
	size_t savedOffset = this->offset;
	if (![self read: data length: length]) {
		return NO;
	}
	this->offset = savedOffset;
	return YES;
}

- (BOOL)peekNoCopy: (NSUInteger)length region: (const void**)region
{
	XPC_THIS_DECL(deserializer);
	size_t savedOffset = this->offset;
	if (![self consume: length region: region]) {
		return NO;
	}
	this->offset = savedOffset;
	return YES;
}

- (BOOL)peekString: (const char**)string
{
	XPC_THIS_DECL(deserializer);
	size_t savedOffset = this->offset;
	if (![self readString: string]) {
		return NO;
	}
	this->offset = savedOffset;
	return YES;
}

- (BOOL)peekU32: (uint32_t*)value
{
	XPC_THIS_DECL(deserializer);
	size_t savedOffset = this->offset;
	if (![self readU32: value]) {
		return NO;
	}
	this->offset = savedOffset;
	return YES;
}

- (BOOL)peekU64: (uint64_t*)value
{
	XPC_THIS_DECL(deserializer);
	size_t savedOffset = this->offset;
	if (![self readU64: value]) {
		return NO;
	}
	this->offset = savedOffset;
	return YES;
}

+ (XPC_CLASS(dictionary)*)process: (dispatch_mach_msg_t)message
{
	XPC_CLASS(deserializer)* deserializer = [[[self class] alloc] initWithMessage: message];
	XPC_CLASS(dictionary)* dict = nil;

	if (!deserializer) {
		goto error_out;
	}

	if (![deserializer readObject: &dict]) {
		goto error_out;
	}

	if (![dict isKindOfClass: [XPC_CLASS(dictionary) class]]) {
		goto error_out;
	}

	dict.incomingPort = deserializer.remotePort;

	[deserializer release];
	return [dict autorelease];

error_out:
	[dict release];
	[deserializer release];
	return nil;
}

+ (instancetype)deserializerWithMessage: (dispatch_mach_msg_t)message
{
	return [[[[self class] alloc] initWithMessage: message] autorelease];
}

@end
