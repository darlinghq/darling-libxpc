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

#import <xpc/util.h>
#import <objc/runtime.h>
#import <xpc/serialization.h>
#include <sys/reason.h>
#import <xpc/objects/connection.h>
#include <sys/stat.h>
#include <stdio.h>
#include <mach-o/dyld.h>

static bool verbose_stub_messages = false;

XPC_LOGGER_DEF(stubs);
XPC_LOGGER_DEF(assumptions);

bool xpc_should_log(void) {
	static bool enabled = true;
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		char* execPath = xpc_copy_main_executable_path();
		// disable syslog within the syslog and aslmanager daemons
		// (so that we don't end up trying to send a message to ourselves)
		if (strcmp(execPath, "/usr/sbin/syslogd") == 0 || strcmp(execPath, "/usr/sbin/aslmanager") == 0) {
			enabled = false;
		}
		free(execPath);
	});

	return enabled;
};

XPC_CLASS(object)* xpc_retain_for_collection(XPC_CLASS(object)* object) {
	// connections aren't retained by collections
	if ([object isKindOfClass: [XPC_CLASS(connection) class]]) {
		return object;
	}
	return [object retain];
};

void xpc_release_for_collection(XPC_CLASS(object)* object) {
	if ([object isKindOfClass: [XPC_CLASS(connection) class]]) {
		return;
	}
	return [object release];
};

const char* xpc_class_name(XPC_CLASS(object)* object) {
	return class_getName([object class]);
};

char* xpc_description_indent(const char* description, bool indentFirstLine) {
	size_t newSize = 0;
	for (size_t i = 0; description[i] != '\0'; ++i) {
		++newSize;
		if (description[i] == '\n') {
			++newSize;
		}
	}
	if (indentFirstLine) {
		++newSize;
	}
	char* newDescription = malloc(sizeof(char) * (newSize + 1));
	if (indentFirstLine) {
		newDescription[0] = '\t';
	}
	for (size_t i = 0, j = indentFirstLine ? 1 : 0; description[i] != '\0'; ++i, ++j) {
		newDescription[j] = description[i];
		if (description[i] == '\n') {
			newDescription[++j] = '\t';
		}
	}
	newDescription[newSize] = '\0';
	return newDescription;
};

size_t xpc_raw_data_hash(const void* data, size_t data_length) {
	if (data_length == 0) {
		return 0x1505;
	}
	size_t result = 0;
	for (size_t i = 0; i < data_length; ++i) {
		uint8_t current = ((uint8_t*)data)[i];
		if (current == 0) {
			break;
		}
		result = (result * 0x21) + current;
	}
	return result;
};

bool xpc_mach_port_is_dead(mach_port_t port) {
	mach_port_urefs_t refs = 0;
	if (MACH_PORT_VALID(port)) {
		mach_port_get_refs(mach_task_self(), port, MACH_PORT_RIGHT_DEAD_NAME, &refs);
	}
	return refs > 0;
};

audit_token_t* xpc_mach_msg_audit_token(mach_msg_header_t* header) {
	mach_msg_trailer_t* trailer = (mach_msg_trailer_t*)((char*)header + round_msg(header->msgh_size));
	if (trailer->msgh_trailer_type == MACH_MSG_TRAILER_FORMAT_0 && trailer->msgh_trailer_size >= sizeof(mach_msg_audit_trailer_t)) {
		return &((mach_msg_audit_trailer_t*)trailer)->msgh_audit;
	}
	return NULL;
};

kern_return_t xpc_mach_port_retain_right(mach_port_name_t port, mach_port_right_t right) {
	if (!MACH_PORT_VALID(port)) {
		return KERN_SUCCESS;
	}
	kern_return_t status = mach_port_mod_refs(mach_task_self(), port, right, 1);
	if (status == KERN_INVALID_RIGHT) {
		status = mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_DEAD_NAME, 1);
	}
	return status;
};

kern_return_t xpc_mach_port_release_right(mach_port_name_t port, mach_port_right_t right) {
	if (!MACH_PORT_VALID(port)) {
		return KERN_SUCCESS;
	}
	kern_return_t status = mach_port_mod_refs(mach_task_self(), port, right, -1);
	if (status == KERN_INVALID_RIGHT) {
		status = mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_DEAD_NAME, -1);
	}
	return status;
};

kern_return_t xpc_mach_port_retain_send(mach_port_t port) {
	return xpc_mach_port_retain_right(port, MACH_PORT_RIGHT_SEND);
};

kern_return_t xpc_mach_port_release_send(mach_port_t port) {
	return xpc_mach_port_release_right(port, MACH_PORT_RIGHT_SEND);
};

kern_return_t xpc_mach_port_make_send(mach_port_t port) {
	if (!MACH_PORT_VALID(port)) {
		return KERN_SUCCESS;
	}
	return mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND);
};

kern_return_t xpc_mach_port_retain_send_once(mach_port_t port) {
	return xpc_mach_port_retain_right(port, MACH_PORT_RIGHT_SEND_ONCE);
};

kern_return_t xpc_mach_port_release_send_once(mach_port_t port) {
	return xpc_mach_port_release_right(port, MACH_PORT_RIGHT_SEND_ONCE);
};

kern_return_t xpc_mach_port_retain_send_any(mach_port_t port) {
	kern_return_t status1 = xpc_mach_port_retain_send(port);
	kern_return_t status2 = xpc_mach_port_retain_send_once(port);
	// if either one of them succeeds, consider it a success
	return (status1 == KERN_SUCCESS || status2 == KERN_SUCCESS) ? KERN_SUCCESS : status1;
};

kern_return_t xpc_mach_port_release_send_any(mach_port_t port) {
	kern_return_t status1 = xpc_mach_port_release_send(port);
	kern_return_t status2 = xpc_mach_port_release_send_once(port);
	// if either one of them succeeds, consider it a success
	return (status1 == KERN_SUCCESS || status2 == KERN_SUCCESS) ? KERN_SUCCESS : status1;
};

kern_return_t xpc_mach_port_release_receive(mach_port_t port) {
	return xpc_mach_port_release_right(port, MACH_PORT_RIGHT_RECEIVE);
};

mach_port_right_t xpc_mach_msg_type_name_to_port_right(mach_msg_type_name_t type_name) {
	switch (type_name) {
		case MACH_MSG_TYPE_MOVE_RECEIVE:
			return MACH_PORT_RIGHT_RECEIVE;
		case MACH_MSG_TYPE_MOVE_SEND:
		case MACH_MSG_TYPE_COPY_SEND:
		case MACH_MSG_TYPE_MAKE_SEND:
			return MACH_PORT_RIGHT_SEND;
		case MACH_MSG_TYPE_MOVE_SEND_ONCE:
		case MACH_MSG_TYPE_MAKE_SEND_ONCE:
			return MACH_PORT_RIGHT_SEND_ONCE;
	}
	return (mach_port_right_t)-1;
};

mach_port_t xpc_mach_port_create_receive(void) {
	mach_port_t port = MACH_PORT_NULL;
	if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port) != KERN_SUCCESS) {
		return MACH_PORT_NULL;
	}
	return port;
};

mach_port_t xpc_mach_port_create_send_receive(void) {
	mach_port_t port = xpc_mach_port_create_receive();
	if (!MACH_PORT_VALID(port)) {
		return MACH_PORT_NULL;
	}
	if (xpc_mach_port_make_send(port) != KERN_SUCCESS) {
		xpc_mach_port_release_receive(port);
		return MACH_PORT_NULL;
	}
	return port;
};

bool xpc_mach_port_is_send_once(mach_port_t port) {
	mach_port_urefs_t refs = 0;
	if (MACH_PORT_VALID(port)) {
		mach_port_get_refs(mach_task_self(), port, MACH_PORT_RIGHT_SEND_ONCE, &refs);
	}
	return refs > 0;
};

XPC_NORETURN
void _xpc_abortv(const char* function, const char* file, size_t line, const char* reason_format, va_list args) {
	char* message = NULL;
	char* reason = NULL;
	if (reason_format == NULL) {
		reason = strdup("aborting for unknown reason");
	} else {
		vasprintf(&reason, reason_format, args);
	}
	asprintf(&message, "libxpc: %s:%zu: %s: %s", file, line, function, reason);
	free(reason);
	abort_with_reason(OS_REASON_LIBXPC, 0, message, 0);
	free(message); // unreachable
};

XPC_NORETURN
void _xpc_abort(const char* function, const char* file, size_t line, const char* reason_format, ...) {
	va_list args;
	va_start(args, reason_format);
	_xpc_abortv(function, file, line, reason_format, args);
	va_end(args); // unreachable
};

XPC_NORETURN
void _xpc_assertion_failed(const char* function, const char* file, size_t line, const char* expression) {
	_xpc_abort(function, file, line, "assertion failed: %s", expression);
};

void xpc_stub_init(void) {
	verbose_stub_messages = getenv("STUB_VERBOSE") != NULL;
};

void _xpc_stub(const char* function, const char* file, size_t line) {
	xpc_log(stubs, "libxpc stub called: %s (at %s:%zu)", function, file, line);

	if (verbose_stub_messages) {
		printf("libxpc stub called: %s (at %s:%zu)\n", function, file, line);
		fflush(stdout);
	}
};

bool xpc_path_is_file(const char* path) {
	struct stat stats;
	if (stat(path, &stats) != 0) {
		return false;
	}
	return S_ISREG(stats.st_mode);
};

char* xpc_copy_main_executable_path(void) {
	char* result = NULL;
	uint32_t resultSize = MAXPATHLEN + 1;

retry:
	result = realloc(result, resultSize);
	if (!result) {
		goto out;
	}

	if (_NSGetExecutablePath(result, &resultSize) != 0) {
		// dyld already set resultSize to the necessary size
		goto retry;
	}

out:
	return result;
};

os_log_t xpc_get_log(void) {
	static os_log_t logger = NULL;
	static dispatch_once_t token;
	dispatch_once(&token, ^{
		logger = os_log_create("org.darlinghq.libxpc", "general");
	});
	return logger;
};

void _xpc_assumption_failed(const char* function, const char* file, size_t line, const char* expression) {
	xpc_log_error(assumptions, "assumption failed in %s at %s:%zu: %s", function, file, line, expression);
};
