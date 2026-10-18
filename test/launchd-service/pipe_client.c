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

#include <xpc/xpc.h>
#include <xpc/endpoint.h>

#include <xpc/private/pipe.h>
#include <xpc/private/endpoint.h>

#include "service.h"

#define client_log(format, ...) printf("piped client: " format "\n", ## __VA_ARGS__)
#define client_error(format, ...) fprintf(stderr, "piped client: " format "\n", ## __VA_ARGS__)
#define reply_log(format, ...) printf("pipe reply handler: " format "\n", ## __VA_ARGS__)
#define reply_error(format, ...) fprintf(stderr, "pipe reply handler: " format "\n", ## __VA_ARGS__)

#include "client_common.h"

// from `util.h`
kern_return_t xpc_mach_port_release_send(mach_port_t port);

static xpc_pipe_t xpc_pipe_create_from_endpoint(xpc_endpoint_t endpoint) {
	xpc_pipe_t pipe = NULL;
	mach_port_t port = MACH_PORT_NULL;

	if (!endpoint || xpc_get_type(endpoint) != (xpc_type_t)XPC_TYPE_ENDPOINT) {
		goto out;
	}

	port = xpc_endpoint_copy_listener_port_4sim(endpoint);
	if (!MACH_PORT_VALID(port)) {
		goto out;
	}

	pipe = xpc_pipe_create_from_port(port, 0);
	xpc_mach_port_release_send(port); // release it because the pipe already copies it

out:
	return pipe;
};

static xpc_pipe_t xpc_dictionary_create_pipe(xpc_object_t xdict, const char* key) {
	return xpc_pipe_create_from_endpoint(xpc_dictionary_get_value(xdict, key));
};

static void error_handler(int status) {
	client_error("error: %s", strerror(status));
};

static void reply_handler(test_service_message_type_t outgoing_message_type, xpc_object_t object) {
	xpc_type_t obj_type = xpc_get_type(object);
	if (obj_type == (xpc_type_t)XPC_TYPE_DICTIONARY) {
		test_service_message_type_t incoming_message_type = xpc_dictionary_get_uint64(object, MESSAGE_TYPE_KEY);

		switch (outgoing_message_type) {
			case test_service_message_type_hello: {
				if (incoming_message_type != test_service_message_type_hello) {
					reply_error("server replied to hello message with invalid message with type: %llu", incoming_message_type);
					return;
				}

				reply_log("server replied to hello message with: %s", xpc_dictionary_get_string(object, HELLO_KEY));
			} break;

			case test_service_message_type_echo: {
				if (incoming_message_type != test_service_message_type_echo) {
					reply_error("server replied to echo message with invalid message with type: %llu", incoming_message_type);
					return;
				}

				char* desc = xpc_copy_description(xpc_dictionary_get_value(object, ECHO_KEY));
				reply_log("server replied to echo message with: %s", desc);
				if (desc) {
					free(desc);
				}
			} break;

			case test_service_message_type_meet_a_new_friend: {
				xpc_pipe_t new_pipe = NULL;
				xpc_object_t message = NULL;
				xpc_object_t reply = NULL;
				int status = 0;

				if (incoming_message_type != test_service_message_type_meet_a_new_friend) {
					reply_error("server replied to meet-a-new-friend message with invalid message with type: %llu", incoming_message_type);
					return;
				}

				new_pipe = xpc_dictionary_create_pipe(object, MEET_A_NEW_FRIEND_KEY);
				if (!new_pipe) {
					reply_log("server didn't have a friend for us to meet :(");
					return;
				}

				message = xpc_dictionary_create(NULL, NULL, 0);
				xpc_dictionary_set_uint64(message, MESSAGE_TYPE_KEY, test_service_message_type_hello);
				xpc_dictionary_set_string(message, HELLO_KEY, "Hello from an anonymous piped client!");

				status = xpc_pipe_routine(new_pipe, message, &reply);

				if (status == 0) {
					reply_handler(test_service_message_type_hello, reply);
					xpc_release(reply);
				} else {
					error_handler(status);
				}
			} break;
		}
	} else {
		reply_error("received non-dictionary object in reply handler: %s\n", xpc_copy_description(object));
		abort();
	}
};

int main(int argc, char** argv) {
	test_service_message_type_t message_type = determine_message_type(argc, argv);
	xpc_pipe_t pipe = xpc_pipe_create(TEST_SERVICE_NAME, 0);
	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);

	xpc_dictionary_set_uint64(message, MESSAGE_TYPE_KEY, message_type);

	switch (message_type) {
		case test_service_message_type_poke: {
			int status = 0;

			status = xpc_pipe_simpleroutine(pipe, message);

			if (status == 0) {
				client_log("poke message sent successfully");
			} else {
				error_handler(status);
			}
		} break;

		case test_service_message_type_hello: {
			xpc_object_t reply = NULL;
			int status = 0;

			xpc_dictionary_set_string(message, HELLO_KEY, "Hello from the piped client!");

			status = xpc_pipe_routine(pipe, message, &reply);

			if (status == 0) {
				reply_handler(message_type, reply);
				xpc_release(reply);
			} else {
				error_handler(status);
			}
		} break;

		case test_service_message_type_echo: {
			xpc_object_t reply = NULL;
			int status = 0;

			xpc_dictionary_set_string(message, ECHO_KEY, "ECHO... Echo... echo.. *whipsers* echo...");

			status = xpc_pipe_routine(pipe, message, &reply);

			if (status == 0) {
				reply_handler(message_type, reply);
				xpc_release(reply);
			} else {
				error_handler(status);
			}
		} break;

		case test_service_message_type_meet_a_new_friend: {
			xpc_object_t reply = NULL;
			int status = 0;

			status = xpc_pipe_routine(pipe, message, &reply);

			if (status == 0) {
				reply_handler(message_type, reply);
				xpc_release(reply);
			} else {
				error_handler(status);
			}
		} break;

		default: {
			client_error("user requested unknown/unsupported message type: %llu", message_type);
			exit(1);
		} break;
	}

	return 0;
};
