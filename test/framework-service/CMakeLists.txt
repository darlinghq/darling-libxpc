# XPCTestFramework.framework: a framework that holds XPC services, for
# framework-xpc-services.c and framework-xpc-instances.c. Both services run the
# same executable; the second one declares multiple instances.
set(framework "libexec/darling/usr/libexec/test/xpc/XPCTestFramework.framework")
set(service "${framework}/Versions/A/XPCServices/XPCFrameworkService.xpc")
set(instance_service "${framework}/Versions/A/XPCServices/XPCFrameworkInstanceService.xpc")

add_darling_library(libxpc_test_framework SHARED framework.c)
set_target_properties(libxpc_test_framework PROPERTIES OUTPUT_NAME "XPCTestFramework" PREFIX "" SUFFIX "")
install(TARGETS libxpc_test_framework DESTINATION "${framework}/Versions/A")

add_darling_executable(libxpc_test_framework_service service.c)
set_target_properties(libxpc_test_framework_service PROPERTIES OUTPUT_NAME "XPCFrameworkService")
target_link_libraries(libxpc_test_framework_service xpc_static objc)
install(TARGETS libxpc_test_framework_service DESTINATION "${service}/Contents/MacOS")
install(FILES Info.plist DESTINATION "${service}/Contents")
install(TARGETS libxpc_test_framework_service DESTINATION "${instance_service}/Contents/MacOS")
install(FILES Instance-Info.plist DESTINATION "${instance_service}/Contents" RENAME Info.plist)
install(FILES Framework-Info.plist DESTINATION "${framework}/Versions/A/Resources" RENAME Info.plist)
InstallSymlink(A "${CMAKE_INSTALL_PREFIX}/${framework}/Versions/Current")
InstallSymlink(Versions/Current/XPCTestFramework "${CMAKE_INSTALL_PREFIX}/${framework}/XPCTestFramework")
InstallSymlink(Versions/Current/Resources "${CMAKE_INSTALL_PREFIX}/${framework}/Resources")
InstallSymlink(Versions/Current/XPCServices "${CMAKE_INSTALL_PREFIX}/${framework}/XPCServices")
