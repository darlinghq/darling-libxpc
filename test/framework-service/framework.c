// Copyright (C) 2026 Lubos Dolezel
//
// The binary of XPCTestFramework.framework, which framework-xpc-services.c
// loads; the framework is there for the XPC service it holds.
int xpc_test_framework_marker(void)
{
	return 42;
}
