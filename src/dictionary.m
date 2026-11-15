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

#import <xpc/objects/dictionary.h>
#import <xpc/util.h>
#import <xpc/private.h>
#import <xpc/connection.h>
#import <xpc/objects/string.h>
#import <xpc/objects/mach_send.h>
#import <xpc/objects/mach_recv.h>
#import <xpc/objects/array.h>
#import <xpc/objects/null.h>
#import <xpc/objects/connection.h>
#import <xpc/serialization.h>
#import <objc/runtime.h>

XPC_CLASS_SYMBOL_DECL(dictionary);

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(dictionary)

XPC_CLASS_HEADER(dictionary);

- (void)dealloc
{
	XPC_THIS_DECL(dictionary);
	self.associatedConnection = nil;
	while (!LIST_EMPTY(&this->head)) {
		xpc_dictionary_entry_t entry = LIST_FIRST(&this->head);
		[self removeEntry: entry];
		xpc_release_for_collection(entry->object);
		free(entry);
	}
	[super dealloc];
}

- (char*)xpcDescription
{
	char* output = NULL;
	size_t count = self.count;

	if (count == 0) {
		asprintf(&output, "<%s: %p> {}", xpc_class_name(self), self);
		return output;
	}

	char** descriptions = malloc(sizeof(char*) * count);

	size_t outputLength = 0;
	outputLength += snprintf(NULL, 0, "<%s: %p> {\n", xpc_class_name(self), self);

	XPC_THIS_DECL(dictionary);
	xpc_dictionary_entry_t current = LIST_FIRST(&this->head);
	for (size_t i = 0; i < count; ++i) {
		char* description = current->object.xpcDescription;
		descriptions[i] = xpc_description_indent(description, false);
		free(description);
		outputLength += snprintf(NULL, 0, "\t%s: %s\n", current->name, descriptions[i]);
		current = LIST_NEXT(current, link);
	}

	outputLength += snprintf(NULL, 0, "}");

	output = malloc(outputLength + 1);

	size_t offset = 0;
	offset += snprintf(output + offset, outputLength + 1 - offset, "<%s: %p> {\n", xpc_class_name(self), self);

	current = LIST_FIRST(&this->head);
	for (size_t i = 0; i < count; ++i) {
		offset += snprintf(output + offset, outputLength + 1 - offset, "\t%s: %s\n", current->name, descriptions[i]);
		free(descriptions[i]);
		current = LIST_NEXT(current, link);
	}
	free(descriptions);

	offset += snprintf(output + offset, outputLength + 1 - offset, "}");

	return output;
}

- (mach_port_t)incomingPort
{
	XPC_THIS_DECL(dictionary);
	return this->incoming_port;
}

- (void)setIncomingPort: (mach_port_t)incomingPort
{
	XPC_THIS_DECL(dictionary);
	this->incoming_port = incomingPort;
}

- (mach_port_t)outgoingPort
{
	XPC_THIS_DECL(dictionary);
	return this->outgoing_port;
}

- (void)setOutgoingPort: (mach_port_t)outgoingPort
{
	XPC_THIS_DECL(dictionary);
	this->outgoing_port = outgoingPort;
}

- (BOOL)expectsReply
{
	return xpc_mach_port_is_send_once(self.incomingPort);
}

- (BOOL)isReply
{
	return xpc_mach_port_is_send_once(self.outgoingPort);
}

- (instancetype)init
{
	if (self = [super init]) {
		XPC_THIS_DECL(dictionary);
		LIST_INIT(&this->head);
		memset(&this->associated_audit_token, 0xff, sizeof(audit_token_t));
	}
	return self;
}

- (instancetype)initWithObjects: (XPC_CLASS(object)* const*)objects forKeys: (const char* const*)keys count: (NSUInteger)count
{
	if (self = [super init]) {
		XPC_THIS_DECL(dictionary);
		LIST_INIT(&this->head);

		for (NSUInteger i = 0; i < count; ++i) {
			[self setObject: objects[i] forKey: keys[i]];
		}
	}
	return self;
}

- (xpc_dictionary_entry_t)entryForKey: (const char*)key
{
	XPC_THIS_DECL(dictionary);
	xpc_dictionary_entry_t entry = NULL;

	LIST_FOREACH(entry, &this->head, link) {
		if (strcmp(entry->name, key) == 0) {
			return entry;
		}
	}

	return NULL;
}

- (void)addEntry: (xpc_dictionary_entry_t)entry
{
	XPC_THIS_DECL(dictionary);
	LIST_INSERT_HEAD(&this->head, entry, link);
	++this->size;
}

- (void)removeEntry: (xpc_dictionary_entry_t)entry
{
	XPC_THIS_DECL(dictionary);
	LIST_REMOVE(entry, link);
	--this->size;
}

- (NSUInteger)count
{
	XPC_THIS_DECL(dictionary);
	return this->size;
}

- (XPC_CLASS(connection)*)associatedConnection
{
	XPC_THIS_DECL(dictionary);
	return objc_loadWeak(&this->associatedConnection);
}

- (void)setAssociatedConnection: (XPC_CLASS(connection)*)associatedConnection
{
	XPC_THIS_DECL(dictionary);
	objc_storeWeak(&this->associatedConnection, associatedConnection);
}

- (XPC_CLASS(object)*)objectForKey: (const char*)key
{
	xpc_dictionary_entry_t entry = [self entryForKey: key];
	if (entry == NULL) {
		return nil;
	}
	return entry->object;
}

- (void)setObject: (XPC_CLASS(object)*)object forKey: (const char*)key
{
	if (object == nil) {
		return [self removeObjectForKey: key];
	}

	xpc_dictionary_entry_t entry = [self entryForKey: key];

	if (entry != NULL) {
		XPC_CLASS(object)* old = entry->object;
		entry->object = xpc_retain_for_collection(object);
		[old release];
		return;
	}

	size_t keyLength = strlen(key);
	entry = malloc(sizeof(struct xpc_dictionary_entry_s) + keyLength + 1);

	if (entry == NULL) {
		// no way to report errors
		return;
	}

	entry->object = xpc_retain_for_collection(object);
	strlcpy(entry->name, key, keyLength + 1);
	[self addEntry: entry];
}

- (void)removeObjectForKey: (const char*)key
{
	xpc_dictionary_entry_t entry = [self entryForKey: key];

	if (entry == NULL) {
		return;
	}

	[self removeEntry: entry];

	free(entry);
}

- (void)enumerateKeysAndObjectsUsingBlock: (void (^)(const char* key, XPC_CLASS(object)* obj, BOOL* stop))block
{
	XPC_THIS_DECL(dictionary);
	xpc_dictionary_entry_t entry = NULL;

	LIST_FOREACH(entry, &this->head, link) {
		BOOL stop = NO;
		block(entry->name, entry->object, &stop);
		if (stop) {
			return;
		}
	}
}

- (XPC_CLASS(string)*)stringForKey: (const char*)key
{
	XPC_CLASS(object)* object = [self objectForKey: key];
	TO_OBJC_CHECKED(string, object, string) {
		return string;
	}
	return nil;
}

- (NSUInteger)hash
{
	XPC_THIS_DECL(dictionary);
	NSUInteger result = 0;
	xpc_dictionary_entry_t entry = NULL;

	LIST_FOREACH(entry, &this->head, link) {
		result += [entry->object hash];
	}

	return result;
}

- (instancetype)copy
{
	XPC_THIS_DECL(dictionary);

	XPC_CLASS(dictionary)* result = [XPC_CLASS(dictionary) new];
	xpc_dictionary_entry_t entry = NULL;

	LIST_FOREACH(entry, &this->head, link) {
		XPC_CLASS(object)* copied = [entry->object copy];
		[result setObject: copied forKey: entry->name];
		[copied release];
	}

	return result;
}

- (void)setAssociatedAuditToken: (audit_token_t*)auditToken
{
	XPC_THIS_DECL(dictionary);

	if (!auditToken) {
		return;
	}

	memcpy(&this->associated_audit_token, auditToken, sizeof(audit_token_t));
}

- (void)copyAssociatedAuditTokenTo: (audit_token_t*)auditToken
{
	XPC_THIS_DECL(dictionary);

	if (!auditToken) {
		return;
	}

	memcpy(auditToken, &this->associated_audit_token, sizeof(audit_token_t));
}

@end

@implementation XPC_CLASS(dictionary) (XPCSerialization)

- (BOOL)serializable
{
	return YES;
}

- (NSUInteger)serializationLength
{
	XPC_THIS_DECL(dictionary);
	NSUInteger total = 0;
	xpc_dictionary_entry_t entry = NULL;

	total += xpc_serial_padded_length(sizeof(xpc_serial_type_t));
	total += xpc_serial_padded_length(sizeof(uint32_t));
	total += xpc_serial_padded_length(sizeof(uint32_t));

	LIST_FOREACH(entry, &this->head, link) {
		XPC_CLASS(object)* object = entry->object;
		if (!object.serializable) {
			object = [XPC_CLASS(null) null];
		}
		total += xpc_serial_padded_length(strlen(entry->name) + 1);
		total += object.serializationLength;
	}

	return total;
}

+ (instancetype)deserialize: (XPC_CLASS(deserializer)*)deserializer
{
	XPC_CLASS(dictionary)* result = nil;
	xpc_serial_type_t type = XPC_SERIAL_TYPE_INVALID;
	uint32_t contentLength = 0;
	uint32_t entryCount = 0;
	NSUInteger contentStartOffset = 0;

	if (![deserializer readU32: &type]) {
		goto error_out;
	}
	if (type != XPC_SERIAL_TYPE_DICT) {
		goto error_out;
	}

	if (![deserializer readU32: &contentLength]) {
		goto error_out;
	}

	// the element/entry count is included in the content length
	contentStartOffset = deserializer.offset;

	if (![deserializer readU32: &entryCount]) {
		goto error_out;
	}

	result = [[[self class] alloc] initWithObjects: NULL forKeys: NULL count: 0];

	for (uint32_t i = 0; i < entryCount; ++i) {
		const char* key = NULL;
		XPC_CLASS(object)* object = nil;
		if (![deserializer readString: &key]) {
			goto error_out;
		}
		if (![deserializer readObject: &object]) {
			goto error_out;
		}
		[result setObject: object forKey: key];
		[object release];
	}

	if (deserializer.offset - contentStartOffset != contentLength) {
		goto error_out;
	}

	return result;

error_out:
	if (result != nil) {
		[result release];
	}
	return nil;
}

- (BOOL)serialize: (XPC_CLASS(serializer)*)serializer
{
	XPC_THIS_DECL(dictionary);
	void* reservedForContentLength = NULL;
	NSUInteger contentStartOffset = 0;
	xpc_dictionary_entry_t entry = NULL;

	if (![serializer writeU32: XPC_SERIAL_TYPE_DICT]) {
		goto error_out;
	}

	if (![serializer reserve: sizeof(uint32_t) region: &reservedForContentLength]) {
		goto error_out;
	}

	// the element/entry count is included in the content length
	contentStartOffset = serializer.offset;

	if (![serializer writeU32: this->size]) {
		goto error_out;
	}

	LIST_FOREACH(entry, &this->head, link) {
		if (![serializer writeString: entry->name]) {
			goto error_out;
		}
		XPC_CLASS(object)* object = entry->object;
		if (!object.serializable) {
			object = [XPC_CLASS(null) null];
		}
		if (![serializer writeObject: object]) {
			goto error_out;
		}
	}

	OSWriteLittleInt32(reservedForContentLength, 0, serializer.offset - contentStartOffset);

	return YES;

error_out:
	return NO;
}

@end

//
// C API
//

XPC_EXPORT
xpc_object_t xpc_dictionary_create(const char* const* keys, const xpc_object_t* values, size_t count) {
	return [[XPC_CLASS(dictionary) alloc] initWithObjects: (XPC_CLASS(object)* const*)values forKeys: keys count: count];
};

XPC_EXPORT
xpc_object_t xpc_dictionary_create_empty(void) {
	return xpc_dictionary_create(NULL, NULL, 0);
}

XPC_EXPORT
xpc_object_t xpc_dictionary_create_reply(xpc_object_t xorig) {
	TO_OBJC_CHECKED(dictionary, xorig, orig) {
		XPC_CLASS(dictionary)* dict = NULL;

		if (!orig.expectsReply) {
			return NULL;
		}

		dict = [XPC_CLASS(dictionary) new];

		dict.outgoingPort = orig.incomingPort;
		orig.incomingPort = MACH_PORT_NULL;

		return dict;
	}
	return NULL;
};

XPC_EXPORT
void xpc_dictionary_set_value(xpc_object_t xdict, const char* key, xpc_object_t value) {
	TO_OBJC_CHECKED(dictionary, xdict, dict) {
		[dict setObject: XPC_CAST(object, value) forKey: key];
	}
};

XPC_EXPORT
xpc_object_t xpc_dictionary_get_value(xpc_object_t xdict, const char* key) {
	TO_OBJC_CHECKED(dictionary, xdict, dict) {
		return [dict objectForKey: key];
	}
	return NULL;
};

XPC_EXPORT
size_t xpc_dictionary_get_count(xpc_object_t xdict) {
	TO_OBJC_CHECKED(dictionary, xdict, dict) {
		return dict.count;
	}
	return 0;
};

XPC_EXPORT
bool xpc_dictionary_apply(xpc_object_t xdict, xpc_dictionary_applier_t applier) {
	TO_OBJC_CHECKED(dictionary, xdict, dict) {
		__block BOOL stoppedEarly = NO;
		[dict enumerateKeysAndObjectsUsingBlock: ^(const char* key, XPC_CLASS(object)* value, BOOL* stop) {
			if (!applier(key, value)) {
				stoppedEarly = *stop = YES;
			}
		}];
		return !stoppedEarly;
	}
	return false;
};

XPC_EXPORT
xpc_connection_t xpc_dictionary_get_remote_connection(xpc_object_t xdict) {
	TO_OBJC_CHECKED(dictionary, xdict, dict) {
		return dict.associatedConnection;
	}
	return NULL;
};

XPC_EXPORT
void xpc_dictionary_get_audit_token(xpc_object_t xdict, audit_token_t* token) {
	TO_OBJC_CHECKED(dictionary, xdict, dict) {
		[dict copyAssociatedAuditTokenTo: token];
	}
};

//
// private C API
//

XPC_EXPORT
xpc_object_t _xpc_dictionary_create_reply_with_port(mach_port_t port) {
	XPC_CLASS(dictionary)* dict = [XPC_CLASS(dictionary) new];
	dict.incomingPort = port;
	return dict;
};

XPC_EXPORT
mach_msg_id_t _xpc_dictionary_extract_reply_msg_id(xpc_object_t xdict) {
	return -1;
};

XPC_EXPORT
mach_port_t _xpc_dictionary_extract_reply_port(xpc_object_t xdict) {
	return MACH_PORT_NULL;
};

XPC_EXPORT
mach_msg_id_t _xpc_dictionary_get_reply_msg_id(xpc_object_t xdict) {
	return -1;
};

XPC_EXPORT
void _xpc_dictionary_set_remote_connection(xpc_object_t xdict, xpc_connection_t xconn) {
	TO_OBJC_CHECKED(dictionary, xdict, dict) {
		TO_OBJC_CHECKED(connection, xconn, conn) {
			dict.associatedConnection = conn;
		}
	}
};

XPC_EXPORT
void _xpc_dictionary_set_reply_msg_id(xpc_object_t xdict, mach_msg_id_t msg_id) {

};

XPC_EXPORT
void xpc_dictionary_apply_f(xpc_object_t xdict, void* context, xpc_dictionary_applier_f applier) {
	xpc_dictionary_apply(xdict, ^bool (const char* key, xpc_object_t value) {
		// can't stop it early
		applier(key, value, context);
		return true;
	});
};

XPC_EXPORT
char* xpc_dictionary_copy_basic_description(xpc_object_t xdict) {
	// returns a string that must freed
	return NULL;
};

XPC_EXPORT
bool xpc_dictionary_expects_reply(xpc_object_t xdict) {
	TO_OBJC_CHECKED(dictionary, xdict, dict) {
		return dict.expectsReply;
	}
	return false;
};

XPC_EXPORT
void xpc_dictionary_handoff_reply(xpc_object_t xdict, dispatch_queue_t queue, dispatch_block_t block) {

};

XPC_EXPORT
void xpc_dictionary_handoff_reply_f(xpc_object_t xdict, dispatch_queue_t queue, void* context, dispatch_function_t function) {

};

XPC_EXPORT
void xpc_dictionary_send_reply(xpc_object_t xdict) {

};

//
// setters
//

#define SIMPLE_SETTER(name, type) \
	XPC_EXPORT \
	void xpc_dictionary_set_ ## name(xpc_object_t xdict, const char* key, type value) { \
		TO_OBJC_CHECKED(dictionary, xdict, dict) { \
			xpc_object_t object = xpc_ ## name ## _create(value); \
			xpc_dictionary_set_value(xdict, key, object); \
			xpc_release(object); \
		} \
	};

SIMPLE_SETTER(bool, bool);
SIMPLE_SETTER(int64, int64_t);
SIMPLE_SETTER(uint64, uint64_t);
SIMPLE_SETTER(double, double);
SIMPLE_SETTER(date, int64_t);
SIMPLE_SETTER(string, const char*);
SIMPLE_SETTER(uuid, const uuid_t);
SIMPLE_SETTER(fd, int);
SIMPLE_SETTER(pointer, void*);

XPC_EXPORT
void xpc_dictionary_set_data(xpc_object_t xdict, const char* key, const void* bytes, size_t length) {
	TO_OBJC_CHECKED(dictionary, xdict, dict) {
		xpc_object_t object = xpc_data_create(bytes, length);
		xpc_dictionary_set_value(xdict, key, object);
		xpc_release(object);
	}
};

XPC_EXPORT
void xpc_dictionary_set_connection(xpc_object_t xdict, const char* key, xpc_connection_t connection) {
	return xpc_dictionary_set_value(xdict, key, connection);
};

XPC_EXPORT
void xpc_dictionary_set_mach_send(xpc_object_t xdict, const char* key, mach_port_t port) {
	xpc_object_t object = xpc_mach_send_create(port);
	xpc_dictionary_set_value(xdict, key, object);
	xpc_release(object);
};

XPC_EXPORT
void xpc_dictionary_set_mach_recv(xpc_object_t xdict, const char* key, mach_port_t recv) {
	xpc_object_t object = xpc_mach_recv_create(recv);
	xpc_dictionary_set_value(xdict, key, object);
	xpc_release(object);
};

//
// getters
//

#define SIMPLE_GETTER(name, type) \
	XPC_EXPORT \
	type xpc_dictionary_get_ ## name(xpc_object_t xdict, const char* key) { \
		xpc_object_t object = xpc_dictionary_get_value(xdict, key); \
		return xpc_ ## name ## _get_value(object); \
	};

SIMPLE_GETTER(bool, bool);
SIMPLE_GETTER(int64, int64_t);
SIMPLE_GETTER(uint64, uint64_t);
SIMPLE_GETTER(double, double);
SIMPLE_GETTER(date, int64_t);
SIMPLE_GETTER(pointer, void*);

XPC_EXPORT
const void* xpc_dictionary_get_data(xpc_object_t xdict, const char* key, size_t* length) {
	xpc_object_t object = xpc_dictionary_get_value(xdict, key);
	if (length != NULL) {
		*length = xpc_data_get_length(object);
	}
	return xpc_data_get_bytes_ptr(object);
};

XPC_EXPORT
const char* xpc_dictionary_get_string(xpc_object_t xdict, const char* key) {
	xpc_object_t object = xpc_dictionary_get_value(xdict, key);
	return xpc_string_get_string_ptr(object);
};

XPC_EXPORT
const uint8_t* xpc_dictionary_get_uuid(xpc_object_t xdict, const char* key) {
	xpc_object_t object = xpc_dictionary_get_value(xdict, key);
	return xpc_uuid_get_bytes(object);
};

XPC_EXPORT
int xpc_dictionary_dup_fd(xpc_object_t xdict, const char* key) {
	xpc_object_t object = xpc_dictionary_get_value(xdict, key);
	return xpc_fd_dup(object);
};

XPC_EXPORT
xpc_connection_t xpc_dictionary_create_connection(xpc_object_t xdict, const char* key) {
	xpc_object_t object = xpc_dictionary_get_value(xdict, key);
	return xpc_connection_create_from_endpoint((xpc_endpoint_t)object);
};

XPC_EXPORT
xpc_object_t xpc_dictionary_get_dictionary(xpc_object_t xdict, const char* key) {
	xpc_object_t object = xpc_dictionary_get_value(xdict, key);
	TO_OBJC_CHECKED(dictionary, object, dict) {
		return dict;
	}
	return NULL;
};

XPC_EXPORT
mach_port_t _xpc_dictionary_extract_mach_send(xpc_object_t xdict, const char* key) {
	xpc_object_t object = xpc_dictionary_get_value(xdict, key);
	TO_OBJC_CHECKED(mach_send, object, send) {
		return xpc_mach_send_extract_right(send);
	}
	return MACH_PORT_NULL;
};

XPC_EXPORT
mach_port_t xpc_dictionary_copy_mach_send(xpc_object_t xdict, const char* key) {
	xpc_object_t object = xpc_dictionary_get_value(xdict, key);
	TO_OBJC_CHECKED(mach_send, object, send) {
		return xpc_mach_send_copy_right(send);
	}
	return MACH_PORT_NULL;
};

XPC_EXPORT
mach_port_t xpc_dictionary_extract_mach_recv(xpc_object_t xdict, const char* key) {
	xpc_object_t object = xpc_dictionary_get_value(xdict, key);
	TO_OBJC_CHECKED(mach_recv, object, recv) {
		return xpc_mach_recv_extract_right(recv);
	}
	return MACH_PORT_NULL;
};

XPC_EXPORT
xpc_object_t xpc_dictionary_get_array(xpc_object_t xdict, const char* key) {
	xpc_object_t object = xpc_dictionary_get_value(xdict, key);
	TO_OBJC_CHECKED(array, object, array) {
		return array;
	}
	return NULL;
};

XPC_EXPORT
xpc_connection_t xpc_dictionary_get_connection(xpc_object_t xdict) {
	return xpc_dictionary_get_remote_connection(xdict);
};
