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

#ifndef __XPC_H__
#define __XPC_H__

#include <dispatch/dispatch.h>
#include <os/object.h>

#include <bsm/audit.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

#define __XPC_INDIRECT__
#include <xpc/base.h>

__BEGIN_DECLS

#define XPC_ARRAY_APPEND ((size_t)(-1))

typedef const struct _xpc_type_s *xpc_type_t;
#ifndef __XPC_BUILDING_XPC__
#define XPC_TYPE(type) const struct _xpc_type_s type
#endif

#if OS_OBJECT_USE_OBJC
OS_OBJECT_DECL(xpc_object);
#ifndef XPC_DECL
#define XPC_DECL(name) typedef xpc_object_t name##_t
#endif
#define XPC_GLOBAL_OBJECT(object) ((OS_OBJECT_BRIDGE xpc_object_t)&(object))
#define XPC_RETURNS_RETAINED
#else
typedef void *xpc_object_t;
#define XPC_DECL(name) typedef struct _##name##_s *name##_t
#define XPC_GLOBAL_OBJECT(object) (&(object))
#define XPC_RETURNS_RETAINED
#endif

typedef bool (^xpc_array_applier_t)(size_t index, xpc_object_t _Nonnull value);
typedef void (^xpc_handler_t)(xpc_object_t object);
typedef bool (^xpc_dictionary_applier_t)(const char *key, xpc_object_t value);

XPC_EXPORT XPC_TYPE(_xpc_type_array);
XPC_EXPORT XPC_TYPE(_xpc_type_bool);
XPC_EXPORT XPC_TYPE(_xpc_type_connection);
XPC_EXPORT XPC_TYPE(_xpc_type_data);
XPC_EXPORT XPC_TYPE(_xpc_type_date);
XPC_EXPORT XPC_TYPE(_xpc_type_dictionary);
XPC_EXPORT XPC_TYPE(_xpc_type_double);
XPC_EXPORT XPC_TYPE(_xpc_type_endpoint);
XPC_EXPORT XPC_TYPE(_xpc_type_error);
XPC_EXPORT XPC_TYPE(_xpc_type_fd);
XPC_EXPORT XPC_TYPE(_xpc_type_int64);
XPC_EXPORT XPC_TYPE(_xpc_type_null);
XPC_EXPORT XPC_TYPE(_xpc_type_pointer);
XPC_EXPORT XPC_TYPE(_xpc_type_shmem);
XPC_EXPORT XPC_TYPE(_xpc_type_string);
XPC_EXPORT XPC_TYPE(_xpc_type_uint64);
XPC_EXPORT XPC_TYPE(_xpc_type_uuid);

XPC_DECL(xpc_connection);
XPC_DECL(xpc_endpoint);

#define XPC_TYPE_ARRAY (&_xpc_type_array)
#define XPC_TYPE_BOOL (&_xpc_type_bool)
#define XPC_TYPE_CONNECTION (&_xpc_type_connection)
#define XPC_TYPE_DATA (&_xpc_type_data)
#define XPC_TYPE_DATE (&_xpc_type_date)
#define XPC_TYPE_DICTIONARY (&_xpc_type_dictionary)
#define XPC_TYPE_DOUBLE (&_xpc_type_double)
#define XPC_TYPE_ENDPOINT (&_xpc_type_endpoint)
#define XPC_TYPE_ERROR (&_xpc_type_error)
#define XPC_TYPE_FD (&_xpc_type_fd)
#define XPC_TYPE_INT64 (&_xpc_type_int64)
#define XPC_TYPE_NULL (&_xpc_type_null)
#define XPC_TYPE_POINTER (&_xpc_type_pointer)
#define XPC_TYPE_SHMEM (&_xpc_type_shmem)
#define XPC_TYPE_STRING (&_xpc_type_string)
#define XPC_TYPE_UINT64 (&_xpc_type_uint64)
#define XPC_TYPE_UUID (&_xpc_type_uuid)

#define XPC_BOOL_TRUE XPC_GLOBAL_OBJECT(_xpc_bool_true)
#define XPC_BOOL_FALSE XPC_GLOBAL_OBJECT(_xpc_bool_false)
#define XPC_ERROR_KEY_DESCRIPTION _xpc_error_key_description

XPC_EXPORT const struct _xpc_bool_s _xpc_bool_true;
XPC_EXPORT const struct _xpc_bool_s _xpc_bool_false;
XPC_EXPORT const char * const _xpc_error_key_description;

typedef void (*xpc_connection_handler_t)(xpc_connection_t connection);

#if !defined(__XPC_BUILDING_XPC__) || !__XPC_BUILDING_XPC__
#include <xpc/endpoint.h>
#if __BLOCKS__
#include <xpc/activity.h>
#include <xpc/connection.h>
#endif
#undef __XPC_INDIRECT__
#include <launch.h>
#endif

xpc_object_t xpc_array_create(xpc_object_t  _Nonnull const *objects, size_t count);
xpc_object_t xpc_bool_create(bool value);
xpc_object_t xpc_data_create(const void *bytes, size_t length);
xpc_object_t xpc_date_create(int64_t interval);
xpc_object_t xpc_dictionary_create(const char *const _Nonnull *keys, xpc_object_t _Nullable const *values, size_t count);
xpc_object_t xpc_double_create(double value);
xpc_object_t xpc_fd_create(int fd);
xpc_object_t xpc_int64_create(int64_t value);
xpc_object_t xpc_null_create(void);
xpc_object_t xpc_pointer_create(void* value);
xpc_object_t xpc_string_create(const char *string);
xpc_object_t xpc_string_create_with_format_and_arguments(const char *fmt, va_list ap);
xpc_object_t xpc_string_create_with_format(const char* format, ...);
xpc_object_t xpc_uint64_create(uint64_t value);
xpc_object_t xpc_uuid_create(const unsigned char *uuid);

int64_t xpc_date_get_value(xpc_object_t xdate);
bool xpc_bool_get_value(xpc_object_t xbool);
double xpc_double_get_value(xpc_object_t xdouble);
int64_t xpc_int64_get_value(xpc_object_t xint);
void* _Nullable xpc_pointer_get_value(xpc_object_t xptr);
const char * xpc_string_get_string_ptr(xpc_object_t xstring);
uint64_t xpc_uint64_get_value(xpc_object_t xuint);
const uint8_t * xpc_uuid_get_bytes(xpc_object_t xuuid);

size_t xpc_string_get_length(xpc_object_t xstring);

xpc_object_t xpc_data_create_with_dispatch_data(dispatch_data_t ddata);
size_t xpc_data_get_bytes(xpc_object_t xdata, void *buffer, size_t off, size_t length);
const void * xpc_data_get_bytes_ptr(xpc_object_t xdata);
size_t xpc_data_get_length(xpc_object_t xdata);

void xpc_array_append_value(xpc_object_t xarray, xpc_object_t value);
bool xpc_array_apply(xpc_object_t xarray, xpc_array_applier_t applier);
size_t xpc_array_get_count(xpc_object_t xarray);
const void * xpc_array_get_data(xpc_object_t xarray, size_t index, size_t *length);
void* _Nullable xpc_array_get_pointer(xpc_object_t xarray, size_t index);
const char * xpc_array_get_string(xpc_object_t xarray, size_t index);
uint64_t xpc_array_get_uint64(xpc_object_t xarray, size_t index);
int64_t xpc_array_get_int64(xpc_object_t xarray, size_t index);
const uint8_t * xpc_array_get_uuid(xpc_object_t xarray, size_t index);
xpc_object_t xpc_array_get_value(xpc_object_t xarray, size_t index);
void xpc_array_set_data(xpc_object_t xarray, size_t index, const void *bytes, size_t length);
void xpc_array_set_pointer(xpc_object_t xarray, size_t index, void* value);
void xpc_array_set_string(xpc_object_t xarray, size_t index, const char *string);
void xpc_array_set_uint64(xpc_object_t xarray, size_t index, uint64_t value);
void xpc_array_set_value(xpc_object_t xarray, size_t index, xpc_object_t value);

bool xpc_dictionary_apply(xpc_object_t xdict, xpc_dictionary_applier_t applier);
xpc_object_t xpc_dictionary_create_reply(xpc_object_t original);
int xpc_dictionary_dup_fd(xpc_object_t xdict, const char *key);
bool xpc_dictionary_get_bool(xpc_object_t xdict, const char *key);
size_t xpc_dictionary_get_count(xpc_object_t xdict);
const void * xpc_dictionary_get_data(xpc_object_t xdict, const char *key, size_t *length);
xpc_object_t xpc_dictionary_get_dictionary(xpc_object_t xdict, const char *key);
double xpc_dictionary_get_double(xpc_object_t xdict, const char *key);
int64_t xpc_dictionary_get_int64(xpc_object_t xdict, const char *key);
xpc_connection_t xpc_dictionary_get_remote_connection(xpc_object_t xdict);
const char * xpc_dictionary_get_string(xpc_object_t xdict, const char *key);
uint64_t xpc_dictionary_get_uint64(xpc_object_t xdict, const char *key);
const uint8_t * xpc_dictionary_get_uuid(xpc_object_t xdict, const char *key);
xpc_object_t xpc_dictionary_get_value(xpc_object_t xdict, const char *key);
void xpc_dictionary_set_bool(xpc_object_t xdict, const char *key, bool value);
void xpc_dictionary_set_data(xpc_object_t xdict, const char *key, const void *bytes, size_t length);
void xpc_dictionary_set_double(xpc_object_t xdict, const char *key, double value);
void xpc_dictionary_set_fd(xpc_object_t xdict, const char *key, int fd);
void xpc_dictionary_set_int64(xpc_object_t xdict, const char *key, int64_t value);
void xpc_dictionary_set_string(xpc_object_t xdict, const char *key, const char *string);
void xpc_dictionary_set_uint64(xpc_object_t xdict, const char *key, uint64_t value);
void xpc_dictionary_set_uuid(xpc_object_t xdict, const char *key, const unsigned char *uuid);
void xpc_dictionary_set_value(xpc_object_t xdict, const char *key, xpc_object_t value);
xpc_connection_t xpc_dictionary_create_connection(xpc_object_t xdict, const char* key);

char * xpc_copy_description(xpc_object_t object);
bool xpc_equal(xpc_object_t object1, xpc_object_t object2);
int xpc_fd_dup(xpc_object_t xfd);
xpc_type_t xpc_get_type(xpc_object_t object);
size_t xpc_hash(xpc_object_t object);
void xpc_main(xpc_connection_handler_t handler);
void xpc_release(xpc_object_t object);
xpc_object_t xpc_retain(xpc_object_t object);
void xpc_transaction_begin(void);
void xpc_transaction_end(void);

// The name of the launchd.plist LaunchEvents entry that an event delivered
// to an event stream handler was set up for.
extern const char* const _xpc_event_key_name;
#define XPC_EVENT_KEY_NAME _xpc_event_key_name

#if __BLOCKS__
void xpc_set_event_stream_handler(const char* stream, dispatch_queue_t targetq, xpc_handler_t handler);
#endif

__END_DECLS

#endif // __XPC_H__ 
