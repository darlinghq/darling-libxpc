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

#import <xpc/objects/activity.h>
#import <xpc/objects/string.h>
#import <xpc/util.h>
#import <xpc/xpc.h>
#import <xpc/activity.h>

XPC_CLASS_SYMBOL_DECL(activity);

// strangely enough, the variables themselves aren't marked as const
#define KEY_DEF(name, string) XPC_EXPORT const char* XPC_ACTIVITY_ ## name = string
#define INTERVAL_DEF(name, seconds) XPC_EXPORT const int64_t XPC_ACTIVITY_INTERVAL_ ## name = seconds

KEY_DEF(ALLOW_BATTERY, "AllowBattery");
KEY_DEF(APP_REFRESH, "AppRefresh");
KEY_DEF(COMMUNICATES_WITH_PAIRED_DEVICE, "CommunicatesWithPairedDevice");
KEY_DEF(DELAY, "Delay");
KEY_DEF(DO_IT_LATER, "DoItLater");
KEY_DEF(EXCLUSIVE, "Exclusive");
KEY_DEF(EXPECTED_DURATION, "ExpectedDuration");
KEY_DEF(GRACE_PERIOD, "GracePeriod");
KEY_DEF(GROUP_CONCURRENCY_LIMIT, "ActivityGroupConcurrencyLimit");
KEY_DEF(GROUP_NAME, "ActivityGroupName");
KEY_DEF(MAY_REBOOT_DEVICE, "MayRebootDevice");
KEY_DEF(POST_INSTALL, "PostInstall");
KEY_DEF(POWER_NAP, "PowerNap");
KEY_DEF(RANDOM_INITIAL_DELAY, "RandomInitialDelay");
KEY_DEF(REPEATING, "Repeating");
KEY_DEF(REPLY_ENDPOINT, "_ReplyEndpoint");
KEY_DEF(SEQUENCE_NUMBER, "_SequenceNumber");
KEY_DEF(SHOULD_WAKE_DEVICE, "ShouldWakeDevice");
KEY_DEF(USER_REQUESTED_BACKUP_TASK, "UserRequestedBackupTask");

// interval
KEY_DEF(INTERVAL, "Interval");
INTERVAL_DEF(1_MIN, 1 * 60);
INTERVAL_DEF(5_MIN, 5 * 60);
INTERVAL_DEF(15_MIN, 15 * 60);
INTERVAL_DEF(30_MIN, 30 * 60);
INTERVAL_DEF(1_HOUR, 1 * 60 * 60);
INTERVAL_DEF(4_HOURS, 4 * 60 * 60);
INTERVAL_DEF(8_HOURS, 8 * 60 * 60);
INTERVAL_DEF(1_DAY, 1 * 24 * 60 * 60);
INTERVAL_DEF(7_DAYS, 7 * 24 * 60 * 60);

// resource intesive
KEY_DEF(CPU_INTENSIVE, "CPUIntensive");
KEY_DEF(DISK_INTENSIVE, "DiskIntensive");
KEY_DEF(MEMORY_INTENSIVE, "MemoryIntensive");

// priority
KEY_DEF(PRIORITY, "Priority");
KEY_DEF(PRIORITY_MAINTENANCE, "Maintenance");
KEY_DEF(PRIORITY_UTILITY, "Utility");

// motion state
KEY_DEF(DESIRED_MOTION_STATE, "MotionState");
KEY_DEF(MOTION_STATE_AUTOMOTIVE, "Automotive");
KEY_DEF(MOTION_STATE_AUTOMOTIVE_MOVING, "AutomotiveMoving");
KEY_DEF(MOTION_STATE_AUTOMOTIVE_STATIONARY, "AutomotiveStationary");
KEY_DEF(MOTION_STATE_CYCLING, "Cycling");
KEY_DEF(MOTION_STATE_RUNNING, "Running");
KEY_DEF(MOTION_STATE_STATIONARY, "Stationary");
KEY_DEF(MOTION_STATE_WALKING, "Walking");

// network transfer
KEY_DEF(NETWORK_TRANSFER_ENDPOINT, "NetworkEndpoint");
KEY_DEF(NETWORK_TRANSFER_PARAMETERS, "NetworkParameters");
KEY_DEF(NETWORK_TRANSFER_SIZE, "NetworkTransferSize");
KEY_DEF(NETWORK_TRANSFER_DIRECTION, "NetworkTransferDirection");
KEY_DEF(NETWORK_TRANSFER_BIDIRECTIONAL, "Bidirectional");
KEY_DEF(NETWORK_TRANSFER_DIRECTION_DOWNLOAD, "Download");
KEY_DEF(NETWORK_TRANSFER_DIRECTION_UPLOAD, "Upload");

// requirements
KEY_DEF(REQUIRES_BUDDY_COMPLETE, "RequiresBuddyComplete");
KEY_DEF(REQUIRES_CLASS_A, "RequiresClassA");
KEY_DEF(REQUIRES_CLASS_B, "RequiresClassB");
KEY_DEF(REQUIRES_CLASS_C, "RequiresClassC");
KEY_DEF(REQUIRE_BATTERY_LEVEL, "RequireBatteryLevel");
KEY_DEF(REQUIRE_HDD_SPINNING, "RequireHDDSpinning");
KEY_DEF(REQUIRE_INEXPENSIVE_NETWORK_CONNECTIVITY, "RequireInexpensiveNetworkConnectivity");
KEY_DEF(REQUIRE_NETWORK_CONNECTIVITY, "RequireNetworkConnectivity");
KEY_DEF(REQUIRE_SCREEN_SLEEP, "RequireScreenSleep");
KEY_DEF(REQUIRE_SIGNIFICANT_USER_INACTIVITY, "RequireSignificantUserInactivity");

// Duet stuff
KEY_DEF(DUET_ACTIVITY_SCHEDULER_DATA, "DASData");
KEY_DEF(DUET_ATTRIBUTE_COST, "DuetAttributeCost");
KEY_DEF(DUET_ATTRIBUTE_NAME, "DuetAttributeName");
KEY_DEF(DUET_ATTRIBUTE_VALUE, "DuetAttributeValue");
KEY_DEF(DUET_RELATED_APPLICATIONS, "DuetRelatedApplications");
KEY_DEF(USES_DUET_POWER_BUDGETING, "DuetPowerBudgeting");

static const struct xpc_string_s _xpc_activity_check_in = {
	.base = {
		XPC_GLOBAL_OBJECT_HEADER(string),
	},
	.byteLength = NSUIntegerMax,
	.string = "<CHECK-IN>",
	.freeWhenDone = false,
};
XPC_GLOBAL_OBJECT_REGISTER(_xpc_activity_check_in);

XPC_EXPORT
const xpc_object_t XPC_ACTIVITY_CHECK_IN = XPC_GLOBAL_OBJECT(_xpc_activity_check_in);

OS_OBJECT_NONLAZY_CLASS
@implementation XPC_CLASS(activity)

XPC_CLASS_HEADER(activity);

@end

//
// C API
//

XPC_EXPORT
void xpc_activity_register(const char *identifier, xpc_object_t criteria, xpc_activity_handler_t handler) {
	xpc_stub();
};

XPC_EXPORT
xpc_object_t xpc_activity_copy_criteria(xpc_activity_t activity) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
void xpc_activity_set_criteria(xpc_activity_t activity, xpc_object_t criteria) {
	xpc_stub();
};

XPC_EXPORT
xpc_activity_state_t xpc_activity_get_state(xpc_activity_t activity) {
	xpc_stub();
	return 0;
};

XPC_EXPORT
bool xpc_activity_set_state(xpc_activity_t activity, xpc_activity_state_t state) {
	xpc_stub();
	return false;
};

XPC_EXPORT
bool xpc_activity_should_defer(xpc_activity_t activity) {
	xpc_stub();
	return false;
};

XPC_EXPORT
void xpc_activity_unregister(const char* identifier) {
	xpc_stub();
};

//
// private C API
//

struct xpc_activity_eligibility_changed_handler_s;

XPC_EXPORT
struct xpc_activity_eligibility_changed_handler_s* xpc_activity_add_eligibility_changed_handler(xpc_activity_t xactivity, void (^handler)()) {
	// the return type is some kind of array or structure that must be freed
	// no clue what the handler parameters are
	xpc_stub();
	return NULL;
};

XPC_EXPORT
dispatch_queue_t xpc_activity_copy_dispatch_queue(xpc_activity_t xactivity) {
	xpc_stub();
	return NULL;
};

XPC_EXPORT
char* xpc_activity_copy_identifier(xpc_activity_t xactivity) {
	// returns a string that must be freed
	xpc_stub();
	return NULL;
};

XPC_EXPORT
void xpc_activity_debug(const char* identifier, uint64_t flags) {
	xpc_stub();
};

XPC_EXPORT
int xpc_activity_defer_until_network_change() {
	// not a stub
	// just returns 0
	// no indiciation of parameters, but probably takes an activity object as an argument
	return 0;
};

XPC_EXPORT
int xpc_activity_defer_until_percentage() {
	// not a stub
	// just returns 0
	return 0;
};

XPC_EXPORT
int xpc_activity_get_percentage() {
	// not a stub
	// just returns 0
	return 0;
};

XPC_EXPORT
void xpc_activity_list(const char* identifier) {
	xpc_stub();
};

XPC_EXPORT
void xpc_activity_remove_eligibility_changed_handler(xpc_activity_t xactivity, struct xpc_activity_eligibility_changed_handler_s* handler_context) {
	xpc_stub();
};

XPC_EXPORT
void xpc_activity_run(const char* identifier) {
	xpc_stub();
};

XPC_EXPORT
void xpc_activity_set_completion_status(xpc_activity_t activity, uint64_t status) {
	xpc_stub();
};

XPC_EXPORT
void xpc_activity_set_network_threshold() {
	// not a stub
	// just does nothing
	// probably has parameters, but no way to tell
};
