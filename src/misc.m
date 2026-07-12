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

#import <xpc/xpc.h>
#import <xpc/util.h>
#import <mach-o/dyld_priv.h>
#define __DISPATCH_INDIRECT__
#import <dispatch/mach_private.h>
#import <os/voucher_private.h>

#include <sys/sysctl.h>

struct os_system_version {
	unsigned int major;
	unsigned int minor;
	unsigned int patch;
};

XPC_EXPORT
struct os_system_version _system_version_fallback = {
	.major = 10,
	.minor = 15,
	.patch = 0,
};

static struct os_system_version current_version = {0};
static dispatch_once_t current_version_once;

int os_system_version_get_current_version(struct os_system_version* out_version);

XPC_EXPORT
bool _availability_version_check(size_t version_count, dyld_build_version_t* versions) {
	if (versions == NULL) {
		return false;
	}

	struct os_system_version system_version;
	if (os_system_version_get_current_version(&system_version) != 0) {
		return false;
	}

	uint32_t packed_version =
		(system_version.major << 16) |
		(system_version.minor << 8) |
		system_version.patch;
	dyld_platform_t active_platform = dyld_get_active_platform();

	for (size_t index = 0; index < version_count; ++index) {
		if (versions[index].platform == active_platform) {
			return packed_version >= versions[index].version;
		}
	}

	return false;
};

XPC_EXPORT
int _system_ios_support_version_copy_string_sysctl(char* out_string) {
	xpc_stub();
	return -1;
};

XPC_EXPORT
bool _system_version_copy_string_plist(char* out_string) {
	xpc_stub();
	return false;
};

// provided string MUST have at least 48 characters
XPC_EXPORT
bool _system_version_copy_string_sysctl(char* out_string) {
	size_t out_string_length = 48;
	return sysctlbyname("kern.osproductversion", out_string, &out_string_length, NULL, 0) == 0;
};

XPC_EXPORT
bool _system_version_parse_string(const char* string, struct os_system_version* out_version) {
	sscanf(string, "%u.%u.%u", &out_version->major, &out_version->minor, &out_version->patch);
	return true;
};

XPC_EXPORT
int os_system_version_get_current_version(struct os_system_version* out_version) {
	dispatch_once(&current_version_once, ^{
		char version_string[48] = {0};

		if (!_system_version_copy_string_sysctl(version_string)) {
			goto fallback;
		}

		if (!_system_version_parse_string(version_string, &current_version)) {
			goto fallback;
		}

		return;

	fallback:
		memcpy(&current_version, &_system_version_fallback, sizeof(struct os_system_version));
	});

	memcpy(out_version, &current_version, sizeof(struct os_system_version));

	return 0;
};

XPC_EXPORT
int os_system_version_sim_get_current_host_version(uint32_t* out_version) {
	// same as with `os_system_version_get_current_version`
	xpc_stub();
	return -1;
};

XPC_EXPORT
xpc_object_t _xpc_payload_create_from_mach_msg(dispatch_mach_msg_t msg, int some_flag) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
void _xpc_spawnattr_pack_string(char* string_but_with_an_offset_of_AEh, uint32_t* offset, size_t* length, const char* string_to_pack) {
	// `string_to_pack` is copied into `string_but_with_an_offset_of_AEh` after offsetting it by 0xae + `*offset`
	// the length of `string_to_pack` (including the null terminator) is added to `*offset` and subtracted from `*length`
	xpc_stub();
};

XPC_EXPORT
void _xpc_spawnattr_pack_string_fragment(char* string_but_with_an_offset_of_AEh, uint32_t* offset, size_t* length, const char* string_to_pack) {
	// same as `_xpc_spawnattr_pack_string`, but doesn't include the null terminator in the math
	xpc_stub();
};

XPC_EXPORT
const char* _xpc_spawnattr_unpack_string(const char* string, size_t length, uint32_t offset) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
char* _xpc_spawnattr_unpack_strings(char* string_but_with_an_offset_of_AEh, size_t length, uint32_t offset, const char** out_strings, size_t strings_array_size) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t place_hold_on_real_loginwindow(void) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_copy_entitlement_for_self(const char* name) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_copy_entitlement_for_token(const char* name, audit_token_t* token) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_copy_entitlements_data_for_token(audit_token_t* token) {
	// returns a data object
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_copy_entitlements_for_pid(pid_t pid) {
	// returns a dictionary
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_copy_entitlements_for_self(void) {
	// returns a dictionary
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_copy_bootstrap(void) {
	// returns a dictionary
	xpc_stub();
	return NULL;
};

XPC_EXPORT
char* xpc_copy_code_signing_identity_for_token(audit_token_t* token) {
	// returns a string that must be freed
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_copy_domain(void) {
	// returns a dictionary with a single entry:
	// "pid": <pid of current process>
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_copy_extension_sdk_entry() {
	// not a stub
	// just returns NULL
	// probably has parameters, but there's no way to tell what they are
	xpc_stub();
	return NULL;
};

XPC_EXPORT
const char* xpc_exit_reason_get_label(int reason) {
	// `reason` is actually an enum value
	// this function just maps the values with their names
	xpc_stub();
	return NULL;
};

XPC_EXPORT
void xpc_generate_audit_token(pid_t i_think_this_is_a_pid, audit_token_t* token) {
	xpc_stub();
};

XPC_EXPORT
xpc_endpoint_t xpc_get_attachment_endpoint(void) {
	xpc_stub();
	return NULL;
};

struct some_return_remote_hooks_struct;
struct some_remote_hooks_struct;

XPC_EXPORT
struct some_return_remote_hooks_struct* xpc_install_remote_hooks(struct some_remote_hooks_struct* hooks) {
	// the return struct is different from the input struct
	// it's probably some hooks for the caller to call back into libxpc
	xpc_stub();
	return NULL;
};

XPC_EXPORT
void xpc_set_idle_handler() {
	// not a stub
	// just does nothing
	// probably has parameters, but there's no way to tell what they are
	xpc_stub();
};

XPC_EXPORT
bool xpc_test_symbols_exported() {
	// not a stub
	// just returns false
	// probably has parameters, but there's no way to tell what they are
	xpc_stub();
	return false;
};

XPC_EXPORT
void xpc_track_activity(void) {
	xpc_stub();
};

XPC_EXPORT
int xpc_receive_mach_msg(dispatch_mach_msg_t msg, bool end_transaction, voucher_t voucher, xpc_connection_t connection, xpc_object_t* out_object) {
	// parameter 2's purpose is a guess
	xpc_stub();
	return -1;
};

XPC_EXPORT
int xpc_receive_remote_msg(void* data, size_t data_length, bool some_flag, void* something, xpc_connection_t connection, void (^oolCallback)()) {
	// parameter 4 is unknown
	// parameter 6 seems to be a callback, but i'm not sure if it's a raw function or a block (probably a block)
	// i'm also unsure what the parameters for the callback are
	xpc_stub();
	return -1;
};

XPC_EXPORT
void* xpc_make_serialization(xpc_object_t object, size_t* out_serialization_length) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
void* xpc_make_serialization_with_ool(xpc_object_t object, size_t* out_serialization_length, uint64_t flags) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_create_from_serialization(void* data, size_t data_length) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_create_from_serialization_with_ool(void* data, size_t data_length, void (^oolCallback)()) {
	// same issue with `oolCallback` as in `xpc_receive_remote_msg`
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_create_reply_with_format_and_arguments(xpc_object_t original, const char* format, va_list args) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_create_reply_with_format(xpc_object_t original, const char* format, ...) {
	va_list args;
	va_start(args, format);
	xpc_object_t result = xpc_create_reply_with_format_and_arguments(original, format, args);
	va_end(args);
	return result;
};

XPC_EXPORT
xpc_object_t xpc_create_with_format_and_arguments(const char* format, va_list args) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_create_with_format(const char* format, ...) {
	va_list args;
	va_start(args, format);
	xpc_object_t result = xpc_create_with_format_and_arguments(format, args);
	va_end(args);
	return result;
};
