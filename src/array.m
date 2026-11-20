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

#import <xpc/objects/array.h>
#import <xpc/util.h>
#import <xpc/private.h>
#import <xpc/connection.h>
#import <xpc/objects/mach_send.h>
#import <xpc/objects/dictionary.h>
#import <xpc/serialization.h>
#import <xpc/objects/null.h>

XPC_CLASS_SYMBOL_DECL(array);

// the old code for xpc_array used each xpc_object as a linked list node
// and stored a head pointer, but this code uses an actual array because:
// 1. random access is constant time with arrays
// 2. xpc_arrays can only grow by appending values
// 3. xpc_arrays can never shrink or have items deleted
// 4. slightly less memory per object

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(array)

XPC_CLASS_HEADER(array);

- (void)dealloc
{
	XPC_THIS_DECL(array);
	for (NSUInteger i = 0; i < this->size; ++i) {
		xpc_release_for_collection(this->array[i]);
	}
	free(this->array);
	[super dealloc];
}

- (char*)xpcDescription
{
	char* output = NULL;
	size_t count = self.count;

	if (count == 0) {
		asprintf(&output, "<%s: %p> []", xpc_class_name(self), self);
		return output;
	}

	char** descriptions = malloc(sizeof(char*) * count);

	size_t outputLength = 0;
	outputLength += snprintf(NULL, 0, "<%s: %p> [\n", xpc_class_name(self), self);
	for (size_t i = 0; i < count; ++i) {
		char* description = self[i].xpcDescription;
		descriptions[i] = xpc_description_indent(description, true);
		free(description);
		outputLength += snprintf(NULL, 0, "%s\n", descriptions[i]);
	}
	outputLength += snprintf(NULL, 0, "]");

	output = malloc(outputLength + 1);

	size_t offset = 0;
	offset += snprintf(output + offset, outputLength + 1 - offset, "<%s: %p> [\n", xpc_class_name(self), self);

	for (size_t i = 0; i < count; ++i) {
		offset += snprintf(output + offset, outputLength + 1 - offset, "%s\n", descriptions[i]);
		free(descriptions[i]);
	}
	free(descriptions);

	offset += snprintf(output + offset, outputLength + 1 - offset, "]");

	return output;
}

- (NSUInteger)count
{
	XPC_THIS_DECL(array);
	return this->size;
}

- (instancetype)initWithObjects: (XPC_CLASS(object)* const*)objects count: (NSUInteger)count
{
	if (self = [super init]) {
		XPC_THIS_DECL(array);

		this->array = malloc(count * sizeof(XPC_CLASS(object)*));

		if (!this->array) {
			[self release];
			return nil;
		}

		this->size = count;
		for (NSUInteger i = 0; i < count; ++i) {
			this->array[i] = xpc_retain_for_collection(XPC_CAST(object, objects[i]));
		}
	}
	return self;
}

- (XPC_CLASS(object)*)objectAtIndex: (NSUInteger)index
{
	XPC_THIS_DECL(array);

	if (index >= this->size) {
		return nil;
	}

	return this->array[index];
}

- (void)addObject: (XPC_CLASS(object)*)object
{
	XPC_THIS_DECL(array);

	// TODO: check what we should actually do when someone tries to append `nil`
	if (object == nil) {
		return;
	}

	XPC_CLASS(object)** expandedArray = realloc(this->array, (this->size + 1) * sizeof(XPC_CLASS(object)*));
	if (expandedArray == NULL) {
		// we have no way to report errors, so just silently leave everything in its previous state
		return;
	}
	this->array = expandedArray;

	this->array[this->size++] = xpc_retain_for_collection(object);
}

- (void)replaceObjectAtIndex: (NSUInteger)index withObject: (XPC_CLASS(object)*)object
{
	XPC_THIS_DECL(array);

	if (index >= this->size) {
		// again, no way to report errors
		return;
	}

	XPC_CLASS(object)* old = this->array[index];
	this->array[index] = xpc_retain_for_collection(object);
	[old release];
}

- (void)enumerateObjectsUsingBlock: (void (^)(XPC_CLASS(object)* object, NSUInteger index, BOOL* stop))block
{
	XPC_THIS_DECL(array);

	for (NSUInteger i = 0; i < this->size; ++i) {
		BOOL stop = NO;
		block(this->array[i], i, &stop);
		if (stop) {
			break;
		}
	}
}

- (XPC_CLASS(object)*)objectAtIndexedSubscript: (NSUInteger)index
{
	return [self objectAtIndex: index];
}

- (void)setObject: (XPC_CLASS(object)*)object atIndexedSubscript: (NSUInteger)index
{
	return [self replaceObjectAtIndex: index withObject: object];
}

- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState*)state objects: (id __unsafe_unretained [])objects count: (NSUInteger)count
{
	if (state->state == 0) {
		XPC_THIS_DECL(array);

		// note that this will only detect mutations of adding new objects, not reassigning existing ones
		state->mutationsPtr = &this->size;
		state->itemsPtr = this->array;
		state->state = 1;
		return this->size;
	} else {
		return 0;
	}
}

- (NSUInteger)hash
{
	XPC_THIS_DECL(array);
	NSUInteger result = 0;

	for (NSUInteger i = 0; i < this->size; ++i) {
		result += [this->array[i] hash];
	}

	return result;
}

- (instancetype)copy
{
	XPC_THIS_DECL(array);

	XPC_CLASS(array)* result = [XPC_CLASS(array) new];

	for (NSUInteger i = 0; i < this->size; ++i) {
		XPC_CLASS(object)* copied = [this->array[i] copy];
		[result addObject: copied];
		[copied release];
	}

	return result;
}

@end

@implementation XPC_CLASS(array) (XPCSerialization)

- (BOOL)serializable
{
	return YES;
}

- (NSUInteger)serializationLength
{
	XPC_THIS_DECL(array);
	NSUInteger total = 0;

	total += xpc_serial_padded_length(sizeof(xpc_serial_type_t));
	total += xpc_serial_padded_length(sizeof(uint32_t));
	total += xpc_serial_padded_length(sizeof(uint32_t));

	for (NSUInteger i = 0; i < this->size; ++i) {
		XPC_CLASS(object)* object = this->array[i];
		if (!object.serializable) {
			object = [XPC_CLASS(null) null];
		}
		total += object.serializationLength;
	}

	return total;
}

+ (instancetype)deserialize: (XPC_CLASS(deserializer)*)deserializer
{
	XPC_CLASS(array)* result = nil;
	xpc_serial_type_t type = XPC_SERIAL_TYPE_INVALID;
	uint32_t contentLength = 0;
	uint32_t entryCount = 0;
	NSUInteger contentStartOffset = 0;

	if (![deserializer readU32: &type]) {
		goto error_out;
	}
	if (type != XPC_SERIAL_TYPE_ARRAY) {
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

	result = [[[self class] alloc] initWithObjects: NULL count: 0];

	for (uint32_t i = 0; i < entryCount; ++i) {
		XPC_CLASS(object)* object = nil;
		if (![deserializer readObject: &object]) {
			goto error_out;
		}
		[result addObject: object];
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
	XPC_THIS_DECL(array);
	void* reservedForContentLength = NULL;
	NSUInteger contentStartOffset = 0;

	if (![serializer writeU32: XPC_SERIAL_TYPE_ARRAY]) {
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

	for (NSUInteger i = 0; i < this->size; ++i) {
		XPC_CLASS(object)* object = this->array[i];
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
xpc_object_t xpc_array_create(const xpc_object_t* objects, size_t count) {
	return [[XPC_CLASS(array) alloc] initWithObjects: (XPC_CLASS(object)* const*)objects count: count];
};

XPC_EXPORT
void xpc_array_set_value(xpc_object_t xarray, size_t index, xpc_object_t value) {
	if (index == XPC_ARRAY_APPEND) {
		return xpc_array_append_value(xarray, value);
	}
	TO_OBJC_CHECKED(array, xarray, array) {
		array[index] = XPC_CAST(object, value);
	}
};

XPC_EXPORT
void xpc_array_append_value(xpc_object_t xarray, xpc_object_t value) {
	TO_OBJC_CHECKED(array, xarray, array) {
		[array addObject: XPC_CAST(object, value)];
	}
};

XPC_EXPORT
size_t xpc_array_get_count(xpc_object_t xarray) {
	TO_OBJC_CHECKED(array, xarray, array) {
		return array.count;
	}
	return 0;
};

XPC_EXPORT
xpc_object_t xpc_array_get_value(xpc_object_t xarray, size_t index) {
	TO_OBJC_CHECKED(array, xarray, array) {
		return array[index];
	}
	return NULL;
};

XPC_EXPORT
bool xpc_array_apply(xpc_object_t xarray, xpc_array_applier_t applier) {
	TO_OBJC_CHECKED(array, xarray, array) {
		for (NSUInteger i = 0; i < array.count; ++i) {
			if (!applier(i, array[i])) {
				return false;
			}
		}
		return true;
	}
	return false;
};

//
// private C API
//

XPC_EXPORT
void xpc_array_apply_f(xpc_object_t xarray, void* context, xpc_array_applier_f applier) {
	xpc_array_apply(xarray, ^bool (size_t index, xpc_object_t value) {
		applier(index, value, context);
		return true;
	});
};

//
// setters
//

#define SIMPLE_SETTER(name, type) \
	XPC_EXPORT \
	void xpc_array_set_ ## name(xpc_object_t xarray, size_t index, type value) { \
		TO_OBJC_CHECKED(array, xarray, array) { \
			xpc_object_t object = xpc_ ## name ## _create(value); \
			xpc_array_set_value(xarray, index, object); \
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
SIMPLE_SETTER(mach_send, mach_port_t); // private setter

XPC_EXPORT
void xpc_array_set_data(xpc_object_t xarray, size_t index, const void* bytes, size_t length) {
	TO_OBJC_CHECKED(array, xarray, array) {
		xpc_object_t object = xpc_data_create(bytes, length);
		xpc_array_set_value(xarray, index, object);
		xpc_release(object);
	}
};

XPC_EXPORT
void xpc_array_set_connection(xpc_object_t xarray, size_t index, xpc_connection_t connection) {
	// see xpc_dictionary_set_connection(): the message carries an endpoint
	xpc_object_t endpoint = xpc_endpoint_create(connection);
	if (endpoint == NULL) {
		return;
	}
	xpc_array_set_value(xarray, index, endpoint);
	xpc_release(endpoint);
};

//
// getters
//

#define SIMPLE_GETTER(name, type) \
	XPC_EXPORT \
	type xpc_array_get_ ## name(xpc_object_t xarray, size_t index) { \
		xpc_object_t object = xpc_array_get_value(xarray, index); \
		return xpc_ ## name ## _get_value(object); \
	};

SIMPLE_GETTER(bool, bool);
SIMPLE_GETTER(int64, int64_t);
SIMPLE_GETTER(uint64, uint64_t);
SIMPLE_GETTER(double, double);
SIMPLE_GETTER(date, int64_t);
SIMPLE_GETTER(pointer, void*);

XPC_EXPORT
const void* xpc_array_get_data(xpc_object_t xarray, size_t index, size_t* length) {
	xpc_object_t object = xpc_array_get_value(xarray, index);
	if (length != NULL) {
		*length = xpc_data_get_length(object);
	}
	return xpc_data_get_bytes_ptr(object);
};

XPC_EXPORT
const char* xpc_array_get_string(xpc_object_t xarray, size_t index) {
	xpc_object_t object = xpc_array_get_value(xarray, index);
	return xpc_string_get_string_ptr(object);
};

XPC_EXPORT
const uint8_t* xpc_array_get_uuid(xpc_object_t xarray, size_t index) {
	xpc_object_t object = xpc_array_get_value(xarray, index);
	return xpc_uuid_get_bytes(object);
};

XPC_EXPORT
int xpc_array_dup_fd(xpc_object_t xarray, size_t index) {
	xpc_object_t object = xpc_array_get_value(xarray, index);
	return xpc_fd_dup(object);
};

XPC_EXPORT
xpc_connection_t xpc_array_create_connection(xpc_object_t xarray, size_t index) {
	xpc_object_t object = xpc_array_get_value(xarray, index);
	return xpc_connection_create_from_endpoint((xpc_endpoint_t)object);
};

//
// private getters
//

XPC_EXPORT
mach_port_t xpc_array_copy_mach_send(xpc_object_t xarray, size_t index) {
	xpc_object_t object = xpc_array_get_value(xarray, index);
	return xpc_mach_send_copy_right(object);
};

XPC_EXPORT
xpc_object_t xpc_array_get_array(xpc_object_t xarray, size_t index) {
	xpc_object_t object = xpc_array_get_value(xarray, index);
	TO_OBJC_CHECKED(array, object, other_array) {
		return other_array;
	}
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_array_get_dictionary(xpc_object_t xarray, size_t index) {
	xpc_object_t object = xpc_array_get_value(xarray, index);
	TO_OBJC_CHECKED(dictionary, object, dict) {
		return dict;
	}
	return NULL;
};
