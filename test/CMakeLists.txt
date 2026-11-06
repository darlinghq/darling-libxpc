add_subdirectory(launchd-service)
add_subdirectory(bundled-service)

set(TEST_SOURCES
	array.m
	base.m
	bool.c
	bundle.c
	data.c
	dictionary.m
	main.c
	plist.c
	string.c
	type.c
)

add_compile_definitions(
	SAMPLE_FRAMEWORK_PATH="/System/Library/Frameworks/Foundation.framework"
	SAMPLE_FRAMEWORK_EXECUTABLE_PATH="/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation"
)

add_custom_command(
	OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/xml_plist_data.h"
	COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/bin2hdr.py" ARGS "xpc_test_xml_plist_data" "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/xml-sample.plist" "${CMAKE_CURRENT_BINARY_DIR}/xml_plist_data.h"
	DEPENDS
		"${CMAKE_CURRENT_SOURCE_DIR}/fixtures/xml-sample.plist"
		"${CMAKE_CURRENT_SOURCE_DIR}/../scripts/bin2hdr.py" # if the generation script changes, update the test data
)
add_custom_command(
	OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/binary_plist_data.h"
	COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/bin2hdr.py" ARGS "xpc_test_binary_plist_data" "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/binary-sample.plist" "${CMAKE_CURRENT_BINARY_DIR}/binary_plist_data.h"
	DEPENDS
		"${CMAKE_CURRENT_SOURCE_DIR}/fixtures/binary-sample.plist"
		"${CMAKE_CURRENT_SOURCE_DIR}/../scripts/bin2hdr.py"
)

add_custom_target(test_libxpc_generate_test_data DEPENDS
	"${CMAKE_CURRENT_BINARY_DIR}/xml_plist_data.h"
	"${CMAKE_CURRENT_BINARY_DIR}/binary_plist_data.h"
)

include_directories(
	"${CMAKE_CURRENT_BINARY_DIR}"
	"${CMAKE_CURRENT_SOURCE_DIR}"
	"${CMAKE_CURRENT_SOURCE_DIR}/ctest"
)

add_darling_executable(test_libxpc ${TEST_SOURCES})

add_dependencies(test_libxpc test_libxpc_generate_test_data)

target_link_libraries(test_libxpc
	# link statically to ensure we always use our copy of libxpc for testing, not the system's
	xpc_static
	objc
)

install(TARGETS test_libxpc DESTINATION libexec/darling/usr/libexec)


add_darling_executable(libxpc_test_nonexistent_service nonexistent-mach-service.c)

target_link_libraries(libxpc_test_nonexistent_service
	xpc_static
	objc
)

install(TARGETS libxpc_test_nonexistent_service DESTINATION libexec/darling/usr/libexec)
