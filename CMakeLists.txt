project(xpc)

cmake_minimum_required(VERSION 3.12)

if(TARGET_i386 OR TARGET_x86_64)
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -msse -msse2 -msse3")
endif()

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -nostdinc -fblocks -fvisibility=hidden")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -D__DARWIN_UNIX03 -fPIC -U_POSIX_C_SOURCE")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -nostdlib")

include_directories(
	${CMAKE_CURRENT_SOURCE_DIR}/include
	${CMAKE_CURRENT_SOURCE_DIR}/internal-include
)

add_compile_definitions(
	__XPC_BUILDING_XPC__
	__XPC_PROJECT_BUILD__
)

add_compile_options(
	-Wno-extern-initializer
	-Wno-gnu-folding-constant
)

add_compile_options(
	-include "${CMAKE_CURRENT_SOURCE_DIR}/internal-include/xpc/prefix.h"
)

set(xpc_sources
	src/bsm_wrappers.c
	src/init.c
	src/reboot3.c

	src/activity.m
	src/array.m
	src/base.m
	src/bool.m
	src/bundle.m
	src/coalition.m
	src/connection.m
	src/data.m
	src/date.m
	src/dictionary.m
	src/double.m
	src/endpoint.m
	src/error.m
	src/event.m
	src/fd.m
	src/file_transfer.m
	src/int64.m
	src/launchd.m
	src/mach_recv.m
	src/mach_send.m
	src/misc.m
	src/null.m
	src/pipe.m
	src/plist.m
	src/pointer.m
	src/runtime.m
	src/serialization.m
	src/service_instance.m
	src/service.m
	src/shmem.m
	src/string.m
	src/transaction.m
	src/type.m
	src/uint64.m
	src/uuid.m
	src/util.m
)

add_darling_object_library(xpc_obj ${xpc_sources})

set(DYLIB_INSTALL_NAME "/usr/lib/system/libxpc.dylib")
add_circular(xpc
	FAT
	OBJECTS
		$<TARGET_OBJECTS:xpc_obj>
	SIBLINGS
		system_c
		system_kernel
		system_blocks
		libdispatch_shared
		platform
		system_malloc
		launch
		system_info
		system_dyld
		unwind
		compiler_rt
		system_pthread
		system_trace
	UPWARD
		# break an upward dependency on libobjc
		# ---
		# note that we don't actually need to intialize it ourselves by calling `objc_init`;
		# libSystem guarantees that we'll be initialized after libdispatch, and libdispatch already initializes libobjc
		objc
)

install(TARGETS xpc DESTINATION libexec/darling/usr/lib/system)

# NOTE: on macOS, these exported symbols are actually in libxpc itself, and are instead reexported by liblaunch.
# this difference shouldn't matter in practice
target_link_options(xpc PRIVATE
	-Wl,-reexported_symbols_list,${CMAKE_CURRENT_SOURCE_DIR}/scripts/reexported-symbols.exp
)

if (ENABLE_TESTS)
	add_darling_static_library(xpc_static
		FAT
		SOURCES
			$<TARGET_OBJECTS:xpc_obj>
	)

	add_subdirectory(test)
endif (ENABLE_TESTS)
