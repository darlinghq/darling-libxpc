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

#include <os/transaction_private.h>
#include <os/object_private.h>
#import <Foundation/NSZone.h>
#import <xpc/xpc.h>
#import <xpc/util.h>

OS_OBJECT_NONLAZY_CLASS
@implementation OS_OBJECT_CLASS(os_transaction)

OS_OBJECT_NONLAZY_CLASS_LOAD

+ (instancetype)allocWithZone: (NSZone*)zone
{
	return (os_transaction_t)_os_object_alloc_realized([self class], sizeof(struct os_transaction_s));
}

- (instancetype)initWithName: (const char*)name
{
	// we CANNOT call `-[super init]`.
	// libdispatch makes `init` crash on `OS_object`s.
	return self;
}

@end

//
// C API
//

XPC_EXPORT
os_transaction_t os_transaction_create(const char* transaction_name) {
	return [[OS_OBJECT_CLASS(os_transaction) alloc] initWithName: transaction_name];
};

XPC_EXPORT
char* os_transaction_copy_description(os_transaction_t transaction) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
int os_transaction_needs_more_time(os_transaction_t transaction) {
	xpc_stub();
	return -1;
};

// these are technically not related to os_transaction,
// but the file is called `transaction.m`, so we'll dump them in here

XPC_EXPORT
void xpc_transaction_begin(void) {
	xpc_stub();
};

XPC_EXPORT
void xpc_transaction_end(void) {
	xpc_stub();
};

//
// private C API
//

XPC_EXPORT
void xpc_transaction_exit_clean(void) {
	xpc_stub();
};

XPC_EXPORT
void xpc_transaction_interrupt_clean_exit(void) {
	xpc_stub();
};

XPC_EXPORT
void xpc_transactions_enable(void) {
	xpc_stub();
};
