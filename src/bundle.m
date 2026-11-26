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

#import <xpc/objects/bundle.h>
#import <xpc/objects/string.h>
#import <xpc/objects/dictionary.h>
#import <xpc/objects/array.h>
#import <xpc/util.h>
#import <xpc/xpc.h>
#import <xpc/private/bundle.h>
#import <xpc/private/plist.h>

#include <Block.h>
#include <sys/stat.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <libgen.h>
#include <mach-o/dyld.h>
#include <os/lock.h>
#include <servers/bootstrap.h>
#include <xpc/launchd_defs.h>
#include <xpc/private/pipe.h>

XPC_LOGGER_DEF(bundle);

#define INFO_DICT_XPC_SERVICE_KEY "XPCService"

XPC_CLASS_SYMBOL_DECL(bundle);

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(bundle)

XPC_CLASS_HEADER(bundle);

+ (XPC_CLASS(bundle)*)mainBundle
{
	char* exec_path = xpc_copy_main_executable_path();
	if (!exec_path) {
		return NULL;
	}
	return [[[[self class] alloc] initWithPath: [XPC_CLASS(string) stringWithCStringNoCopy: exec_path freeWhenDone: YES]] autorelease];
}

+ (BOOL)pathIsBundleRoot: (XPC_CLASS(string)*)path
{
	// frameworks are special
	//
	// in either case, however, we can tell if it's the bundle root if it contains an Info.plist (it's required for all bundles).
	// the difference is just in whether it's directly in the root or in a `Contents` directory.
	if (strcmp(path.pathExtension, "framework") == 0) {
		if (xpc_path_is_file([path stringByAppendingPathComponent: "Info.plist"].CString)) {
			return YES;
		}
	} else {
		if (xpc_path_is_file([path stringByAppendingPathComponent: "Contents/Info.plist"].CString)) {
			return YES;
		}
	}
	return NO;
}

+ (XPC_CLASS(string)*)bundleRootFromPath: (XPC_CLASS(string)*)path
{
	while (![path isEqualToString: "/"]) {
		if ([[self class] pathIsBundleRoot: path]) {
			return path;
		}
		path = [path stringByDeletingLastPathComponent];
	}
	return nil;
}

- (void)dealloc
{
	XPC_THIS_DECL(bundle);

	[this->bundle_path release];
	[this->executable_path release];
	[this->info_dictionary release];
	[this->services release];

	[super dealloc];
}

- (XPC_CLASS(string)*)bundlePath
{
	XPC_THIS_DECL(bundle);
	return this->bundle_path;
}

- (void)setBundlePath: (XPC_CLASS(string)*)bundlePath
{
	XPC_THIS_DECL(bundle);
	[this->bundle_path release];
	this->bundle_path = [bundlePath retain];
}

- (XPC_CLASS(string)*)executablePath
{
	XPC_THIS_DECL(bundle);
	return this->executable_path;
}

- (void)setExecutablePath: (XPC_CLASS(string)*)executablePath
{
	XPC_THIS_DECL(bundle);
	[this->executable_path release];
	this->executable_path = [executablePath retain];
}

- (XPC_CLASS(dictionary)*)infoDictionary
{
	XPC_THIS_DECL(bundle);
	return this->info_dictionary;
}

- (void)setInfoDictionary: (XPC_CLASS(dictionary)*)infoDictionary
{
	XPC_THIS_DECL(bundle);
	[this->info_dictionary release];
	this->info_dictionary = [infoDictionary retain];
}

- (int)error
{
	XPC_THIS_DECL(bundle);
	return this->error;
}

- (void)setError: (int)error
{
	XPC_THIS_DECL(bundle);
	this->error = error;
}

- (BOOL)isFramework
{
	XPC_THIS_DECL(bundle);
	return this->is_framework;
}

- (XPC_CLASS(string)*)infoPath
{
	XPC_CLASS(string)* path = nil;
	if (self.isFramework) {
		path = [self.bundlePath stringByAppendingPathComponent: "Info.plist"];
	} else {
		path = [self.bundlePath stringByAppendingPathComponent: "Contents/Info.plist"];
	}
	return [path stringByResolvingSymlinksInPath];
}

- (instancetype)initWithPath: (XPC_CLASS(string)*)path
{
	if (self = [super init]) {
		XPC_THIS_DECL(bundle);

		self.bundlePath = [[self class] bundleRootFromPath: path];
		if (!self.bundlePath) {
			// if we couldn't find an Info.plist anywhere, let's just blindly trust the user's input
			self.bundlePath = path;
		}

		self.infoDictionary = [XPC_CLASS(dictionary) new];

		this->is_framework = strcmp(self.bundlePath.pathExtension, "framework") == 0;
	}
	return self;
}

- (XPC_CLASS(string)*)pathForResource: (const char*)name ofType: (const char*)type
{
	return [XPC_CLASS(string) stringWithFormat: "%s/%s.%s", self.bundlePath.CString, name, type];
}

- (XPC_CLASS(string)*)pathForSubdirectoryOfType: (xpc_bundle_subdirectory_type_t)type
{
	switch (type) {
		case xpc_bundle_subdirectory_type_xpc_services: {
			return [[self.bundlePath stringByAppendingPathComponent: (self.isFramework) ? "XPCServices" : "Contents/XPCServices"] stringByResolvingSymlinksInPath];
		} break;

		default:
			return nil;
	}
}

- (XPC_CLASS(string)*)resolveExecutableName
{
	XPC_CLASS(string)* result = nil;

	// first try the most common one
	result = [[[self.infoDictionary stringForKey: "CFBundleExecutable"] retain] autorelease];
	if (!result) {
		// then try the other one
		result = [[[self.infoDictionary stringForKey: "NSExecutable"] retain] autorelease];
		if (!result) {
			// finally, if all else fails, try to use the same name as the bundle
			result = [[XPC_CLASS(string) stringWithCString: self.bundlePath.lastPathComponent] stringByDeletingPathExtension];
		}
	}

	return result;
}

- (void)resolveInternal: (xpc_object_t)plist
{
	XPC_THIS_DECL(bundle);

	if (!plist) {
		self.error = xpc_bundle_error_failed_to_read_plist;
		return;
	}

	if (!XPC_CHECK(dictionary, plist)) {
		self.error = xpc_bundle_error_invalid_plist;
		return;
	}

	dispatch_once(&this->resolve_once, ^{
		XPC_CLASS(string)* xpcServicesPath = [self pathForSubdirectoryOfType: xpc_bundle_subdirectory_type_xpc_services];
		DIR* xpcServicesDir = NULL;
		struct dirent* xpcServiceDirent = NULL;
		XPC_CLASS(string)* executableDirTmp = nil;

		self.infoDictionary = XPC_CAST(dictionary, plist);

		// cache the executable path
		executableDirTmp = (self.isFramework) ? self.bundlePath : [self.bundlePath stringByAppendingPathComponent: "Contents/MacOS"];
		self.executablePath = [[executableDirTmp stringByAppendingPathComponent: [self resolveExecutableName].CString] stringByResolvingSymlinksInPath];

		// resolve XPC services
		this->services = [XPC_CLASS(array) new];
		xpcServicesDir = opendir(xpcServicesPath.CString);
		if (xpcServicesDir) {
			while ((xpcServiceDirent = readdir(xpcServicesDir))) {
				@autoreleasepool {
					XPC_CLASS(string)* fullPath = [xpcServicesPath stringByAppendingPathComponent: xpcServiceDirent->d_name];
					if (strcmp(fullPath.pathExtension, "xpc") == 0) {
						XPC_CLASS(bundle)* serviceBundle = [[XPC_CLASS(bundle) alloc] initWithPath: fullPath];
						[serviceBundle resolve];
						if (serviceBundle) {
							[this->services addObject: serviceBundle];
						}
						[serviceBundle release];
					}
				}
			}
			closedir(xpcServicesDir);
		}
	});
}

- (void)resolve
{
	int fd = -1;
	struct stat plist_stat;
	void* buffer = NULL;
	xpc_object_t plist = NULL;

	if (!xpc_path_is_file(self.infoPath.CString)) {
		// no Info.plist; let's continue the resolution with an empty plist
		plist = [XPC_CLASS(dictionary) new];
	} else {
		fd = open(self.infoPath.CString, O_RDONLY);

		if (fd < 0) {
			self.error = xpc_bundle_error_failed_to_read_plist;
			return;
		}

		if (fstat(fd, &plist_stat) < 0) {
			self.error = xpc_bundle_error_failed_to_read_plist;
			close(fd);
			return;
		}

		buffer = malloc(plist_stat.st_size);
		if (!buffer) {
			self.error = xpc_bundle_error_failed_to_read_plist;
			close(fd);
			return;
		}

		if (read(fd, buffer, plist_stat.st_size) != plist_stat.st_size) {
			self.error = xpc_bundle_error_failed_to_read_plist;
			free(buffer);
			close(fd);
			return;
		}

		plist = xpc_create_from_plist(buffer, plist_stat.st_size);

		free(buffer);
		close(fd);
	}

	[self resolveInternal: plist];
	[plist release];
}

- (void)resolveOnQueue: (dispatch_queue_t)resolutionQueue callbackQueue: (dispatch_queue_t)callbackQueue callback: (void(^)(void))callback
{
	int fd = -1;

	if (!xpc_path_is_file(self.infoPath.CString)) {
		// no Info.plist; let's continue the resolution with an empty plist
		callback = Block_copy(callback);
		dispatch_async(resolutionQueue, ^{
			xpc_object_t plist = [XPC_CLASS(dictionary) new];
			[self resolveInternal: plist];
			[plist release];
			dispatch_async(callbackQueue, callback);
			Block_release(callback);
		});
		return;
	}

	fd = open(self.infoPath.CString, O_RDONLY);

	if (fd < 0) {
		self.error = xpc_bundle_error_failed_to_read_plist;
		dispatch_async(callbackQueue, callback);
		return;
	}

	callback = Block_copy(callback);

	xpc_create_from_plist_descriptor(fd, resolutionQueue, ^(xpc_object_t plist) {
		@autoreleasepool {
			close(fd);
			[self resolveInternal: plist];
			dispatch_async(callbackQueue, callback);
			Block_release(callback);
		}
	});
}

@end

//
// private C API
//

XPC_EXPORT
xpc_object_t xpc_bundle_copy_info_dictionary(xpc_object_t xbundle) {
	return [xpc_bundle_get_info_dictionary(xbundle) retain];
};

XPC_EXPORT
char* xpc_bundle_copy_resource_path(xpc_object_t xbundle, const char* name, const char* type) {
	TO_OBJC_CHECKED(bundle, xbundle, bundle) {
		@autoreleasepool {
			XPC_CLASS(string)* path = [bundle pathForResource: name ofType: type];
			return path ? strdup(path.CString) : NULL;
		}
	}
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_bundle_copy_services(xpc_object_t xbundle) {
	// doesn't actually copy the array; only retains it
	xpc_stub();
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_bundle_create(const char* path, unsigned int flags) {
	@autoreleasepool {
		return [[XPC_CLASS(bundle) alloc] initWithPath: [XPC_CLASS(string) stringWithCString: path]];
	}
};

XPC_EXPORT
xpc_object_t xpc_bundle_create_from_origin(unsigned int origin, const char* path) {
	@autoreleasepool {
		return [[XPC_CLASS(bundle) alloc] initWithPath: [XPC_CLASS(string) stringWithCString: path]];
	}
};

XPC_EXPORT
xpc_object_t xpc_bundle_create_main(void) {
	@autoreleasepool {
		return [[XPC_CLASS(bundle) mainBundle] retain];
	}
};

XPC_EXPORT
int xpc_bundle_get_error(xpc_object_t xbundle) {
	TO_OBJC_CHECKED(bundle, xbundle, bundle) {
		return bundle.error;
	}
	return 0;
};

XPC_EXPORT
const char* xpc_bundle_get_executable_path(xpc_object_t xbundle) {
	TO_OBJC_CHECKED(bundle, xbundle, bundle) {
		return bundle.executablePath.CString;
	}
	return NULL;
};

XPC_EXPORT
xpc_object_t xpc_bundle_get_info_dictionary(xpc_object_t xbundle) {
	TO_OBJC_CHECKED(bundle, xbundle, bundle) {
		return bundle.infoDictionary;
	}
	return NULL;
};

XPC_EXPORT
const char* xpc_bundle_get_path(xpc_object_t xbundle) {
	TO_OBJC_CHECKED(bundle, xbundle, bundle) {
		return bundle.bundlePath.CString;
	}
	return NULL;
};

XPC_EXPORT
uint64_t xpc_bundle_get_property(xpc_object_t xbundle, unsigned int property) {
	// unsure about the return type; it can actually return both integers and pointers
	xpc_stub();
	return 0;
};

XPC_EXPORT
xpc_object_t xpc_bundle_get_xpcservice_dictionary(xpc_object_t xbundle) {
	TO_OBJC_CHECKED(bundle, xbundle, bundle) {
		return [bundle.infoDictionary objectForKey: INFO_DICT_XPC_SERVICE_KEY];
	}
	return NULL;
};

XPC_EXPORT
void xpc_bundle_populate(xpc_object_t xbundle, xpc_object_t info_dictionary, xpc_object_t services_array) {
	xpc_stub();
};

XPC_EXPORT
void xpc_bundle_resolve(xpc_object_t xbundle, dispatch_queue_t callback_queue, void* context, xpc_bundle_resolution_callback_f callback) {
	return xpc_bundle_resolve_on_queue(xbundle, callback_queue, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), context, callback);
};

XPC_EXPORT
void xpc_bundle_resolve_on_queue(xpc_object_t xbundle, dispatch_queue_t callback_queue, dispatch_queue_t resolution_queue, void* context, xpc_bundle_resolution_callback_f callback) {
	TO_OBJC_CHECKED(bundle, xbundle, bundle) {
		@autoreleasepool {
			return [bundle resolveOnQueue: resolution_queue callbackQueue: callback_queue callback: ^{
				callback(bundle, bundle.error, context);
			}];
		}
	}
};

XPC_EXPORT
void xpc_bundle_resolve_sync(xpc_object_t xbundle) {
	TO_OBJC_CHECKED(bundle, xbundle, bundle) {
		@autoreleasepool {
			return [bundle resolve];
		}
	}
};

//
// XPC services in frameworks
//
// A framework can hold XPC services (WebKit's web content and networking
// processes are some), and a process that has loaded the framework can connect
// to them by name; before it loads the framework it can't (observed on macOS
// 26.7.3; test: test/framework-xpc-services.c). launchd keeps the services a
// process can see in its domain, so the services directory of each framework
// that is loaded is sent to launchd before a connection looks a name up.
//
// The dyld callback only notes the directories: it runs with dyld's lock held,
// possibly before the Objective-C runtime is ready, so it can't send messages.
//

static os_unfair_lock pending_services_lock = OS_UNFAIR_LOCK_INIT;
static char** pending_services_dirs = NULL;
static size_t pending_services_count = 0;
static size_t pending_services_capacity = 0;

static void note_services_directory(const char* dir) {
	char* copy = strdup(dir);
	if (!copy) {
		return;
	}
	os_unfair_lock_lock(&pending_services_lock);
	if (pending_services_count == pending_services_capacity) {
		size_t capacity = pending_services_capacity ? pending_services_capacity * 2 : 4;
		char** grown = realloc(pending_services_dirs, capacity * sizeof(char*));
		if (!grown) {
			os_unfair_lock_unlock(&pending_services_lock);
			free(copy);
			return;
		}
		pending_services_dirs = grown;
		pending_services_capacity = capacity;
	}
	pending_services_dirs[pending_services_count++] = copy;
	os_unfair_lock_unlock(&pending_services_lock);
}

static void image_added(const struct mach_header* header, intptr_t slide) {
	Dl_info info;
	if (!dladdr(header, &info) || !info.dli_fname) {
		return;
	}

	// The services are next to the binary of a framework: in
	// X.framework/Versions/<v>/ or, for a shallow framework, in X.framework/.
	char binary[PATH_MAX];
	if (strlcpy(binary, info.dli_fname, sizeof(binary)) >= sizeof(binary)) {
		return;
	}
	const char* binary_dir = dirname(binary);
	if (!binary_dir || !strstr(binary_dir, ".framework")) {
		return;
	}
	size_t length = strlen(binary_dir);
	const char* framework_end = strstr(binary_dir, ".framework");
	const char* after = framework_end + strlen(".framework");
	if (*after != '\0' && strncmp(after, "/Versions/", strlen("/Versions/")) != 0) {
		return;
	}

	char dir[PATH_MAX];
	if (snprintf(dir, sizeof(dir), "%.*s/XPCServices", (int)length, binary_dir) >= (int)sizeof(dir)) {
		return;
	}
	char resolved[PATH_MAX];
	struct stat st;
	if (!realpath(dir, resolved) || stat(resolved, &st) != 0 || !S_ISDIR(st.st_mode)) {
		return;
	}
	note_services_directory(resolved);
}

static int add_services_directory(const char* dir) {
	xpc_pipe_t pipe = xpc_pipe_create_from_port(bootstrap_port, 0);
	if (!pipe) {
		return EPIPE;
	}

	xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_uint64(request, XPC_PROCESS_ROUTINE_KEY_OP, XPC_PROCESS_ADD_SERVICES_DIRECTORY);
	xpc_dictionary_set_string(request, XPC_PROCESS_ROUTINE_KEY_PATH, dir);

	xpc_object_t reply = NULL;
	int status = xpc_pipe_routine(pipe, request, &reply);
	xpc_release(request);
	xpc_release(pipe);

	if (status == 0) {
		status = (int)xpc_dictionary_get_uint64(reply, XPC_PROCESS_ROUTINE_KEY_ERROR);
	}
	if (reply) {
		xpc_release(reply);
	}
	return status;
}

void xpc_bundle_services_init(void) {
	_dyld_register_func_for_add_image(image_added);
}

void xpc_bundle_services_register_loaded(void) {
	os_unfair_lock_lock(&pending_services_lock);
	char** dirs = pending_services_dirs;
	size_t count = pending_services_count;
	pending_services_dirs = NULL;
	pending_services_count = 0;
	pending_services_capacity = 0;
	os_unfair_lock_unlock(&pending_services_lock);

	for (size_t i = 0; i < count; i++) {
		int status = add_services_directory(dirs[i]);
		if (status != 0) {
			xpc_log_error(bundle, "failed to add the XPC services in \"%s\": %d", dirs[i], status);
		}
		free(dirs[i]);
	}
	free(dirs);
}

// Adds the XPC services of the bundle at `path` (an application or a
// framework) to the process's domain.
XPC_EXPORT
void xpc_add_bundle(const char* path, unsigned int flags) {
	if (!path) {
		return;
	}
	size_t length = strlen(path);
	bool framework = length >= strlen(".framework") && strcmp(path + length - strlen(".framework"), ".framework") == 0;
	char dir[PATH_MAX];
	if (snprintf(dir, sizeof(dir), "%s/%s", path, framework ? "XPCServices" : "Contents/XPCServices") >= (int)sizeof(dir)) {
		return;
	}
	char resolved[PATH_MAX];
	if (!realpath(dir, resolved)) {
		return;
	}
	(void)add_services_directory(resolved);
};

XPC_EXPORT
void xpc_add_bundles_for_domain(xpc_object_t domain, xpc_object_t bundles) {
	xpc_stub();
};
