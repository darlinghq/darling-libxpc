#ifndef XPC_LAUNCHD_H
#define XPC_LAUNCHD_H

typedef int xpc_service_type_t;
typedef int xpc_jetsam_band_t;
typedef char event_name_t[100];

enum {
	XPC_JETSAM_BAND_SUSPENDED,
	XPC_JETSAM_BAND_BACKGROUND_OPPORTUNISTIC,
	XPC_JETSAM_BAND_BACKGROUND,
	XPC_JETSAM_BAND_MAIL,
	XPC_JETSAM_BAND_PHONE,
	XPC_JETSAM_BAND_UI_SUPPORT,
	XPC_JETSAM_BAND_FOREGROUND_SUPPORT,
	XPC_JETSAM_BAND_FOREGROUND,
	XPC_JETSAM_BAND_AUDIO,
	XPC_JETSAM_BAND_ACCESSORY,
	XPC_JETSAM_BAND_CRITICAL,
	XPC_JETSAM_BAND_TELEPHONY,
	XPC_JETSAM_BAND_LAST = XPC_JETSAM_BAND_TELEPHONY,
};

typedef enum {
        XPC_EVENT_GET_NAME,
        XPC_EVENT_SET,
        XPC_EVENT_COPY,
        XPC_EVENT_CHECK_IN,
        XPC_EVENT_LOOK_UP,
        XPC_EVENT_PROVIDER_CHECK_IN,
        XPC_EVENT_PROVIDER_SET_STATE,
        XPC_EVENT_COPY_ENTITLEMENTS
} xpc_event_t;

typedef enum {
        XPC_PROCESS_JETSAM_SET_BAND,
        XPC_PROCESS_JETSAM_SET_MEMORY_LIMIT,
        XPC_PROCESS_SERVICE_ATTACH,
        XPC_PROCESS_SERVICE_DETACH,
        XPC_PROCESS_SERVICE_GET_PROPERTIES,
        XPC_PROCESS_SERVICE_KILL
} xpc_jetsam_t;

#define XPC_SERVICE_TYPE_BUNDLED 0xBADDCAFE
#define XPC_SERVICE_TYPE_LAUNCHD 0xBABECAFE
#define XPC_SERVICE_TYPE_APP     0xDEADCAFE
#define XPC_SERVICE_TYPE_ENTITLEMENT_ATTACH     0x00DEAD00


#define XPC_SERVICE_ENV_ATTACHED "XPC_SERVICE_ENV_ATTACHED"
#define XPC_SERVICE_RENDEZVOUS_TOKEN "XPC_SERVICE_RENDEZVOUS_TOKEN"

#define XPC_EVENT_ROUTINE_KEY_STREAM "XPC key stream"
#define XPC_EVENT_ROUTINE_KEY_TOKEN "XPC key token"
#define XPC_EVENT_ROUTINE_KEY_NAME "XPC key name"
#define XPC_EVENT_ROUTINE_KEY_ENTITLEMENTS "XPC key entitlements"
#define XPC_EVENT_ROUTINE_KEY_EVENT "XPC key event"
#define XPC_EVENT_ROUTINE_KEY_EVENTS "XPC key events"
#define XPC_EVENT_ROUTINE_KEY_FLAGS "XPC key flags"
#define XPC_EVENT_ROUTINE_KEY_PORT "XPC key port"
#define XPC_EVENT_ROUTINE_KEY_STATE "XPC key state"
#define XPC_EVENT_ROUTINE_KEY_OP "XPC key op"
#define XPC_EVENT_ROUTINE_KEY_ERROR "XPC key error"
#define XPC_PROCESS_ROUTINE_KEY_LABEL "XPC process key label"
#define XPC_PROCESS_ROUTINE_KEY_ERROR "XPC process key error"
#define XPC_PROCESS_ROUTINE_KEY_HANDLE "XPC process key handle"
#define XPC_PROCESS_ROUTINE_KEY_NAME "XPC process key name"
#define XPC_PROCESS_ROUTINE_KEY_PATH "XPC process key path"
#define XPC_PROCESS_ROUTINE_KEY_ARGV "XPC process key argv"
#define XPC_PROCESS_ROUTINE_KEY_TYPE "XPC process key type"
#define XPC_PROCESS_ROUTINE_KEY_OP "XPC process key op"
#define XPC_PROCESS_ROUTINE_KEY_PID "XPC process key pid"
#define XPC_PROCESS_ROUTINE_KEY_RCDATA "XPC process key rcdata"
#define XPC_PROCESS_ROUTINE_KEY_SIGNAL "XPC process key signal"
#define XPC_PROCESS_ROUTINE_KEY_PRIORITY_BAND "XPC process key priority band"
#define XPC_PROCESS_ROUTINE_KEY_MEMORY_LIMIT "XPC process key memory limit"
#define XPC_SERVICE_ENTITLEMENT_ATTACH "XPC service entitlement attach"
#define XPC_SERVICE_RENDEZVOUS_TOKEN "XPC service rendezvous token"
#define XPC_PROCESS_ROUTINE_KEY_NEW_INSTANCE_PORT "XPC process key new instance port"
#define XPC_SERVICE_ENV_ATTACHED "XPC service env attached"

#define XPC_EVENT_FLAG_ENTITLEMENTS 1

#define EXNOMEM 1
#define EXINVAL 2
#define EXSRCH 3
#define EXMAX EXSRCH

#endif
