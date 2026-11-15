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

#include "ctest-plus.h"
#include <xpc/private.h>
#include "test-util.h"

CTEST_DATA(dictionary) {
	const char* keys[OBJECT_COUNT];
	xpc_object_t objects[OBJECT_COUNT];
	xpc_object_t dict;
};

CTEST_SETUP(dictionary) {
	create_keys(data->keys, OBJECT_COUNT);
	create_objects(data->objects, OBJECT_COUNT);
	data->dict = xpc_dictionary_create(data->keys, data->objects, OBJECT_COUNT);
};

CTEST_TEARDOWN(dictionary) {
	xpc_release(data->dict);
	release_objects(data->objects, OBJECT_COUNT);
	release_keys(data->keys, OBJECT_COUNT);
};

CTEST(dictionary, create_empty) {
	xpc_object_t dict = xpc_dictionary_create(NULL, NULL, 0);
	ASSERT_NOT_NULL(dict);
	ASSERT_EQUAL_U(0, xpc_dictionary_get_count(dict));
	xpc_release(dict);

	dict = xpc_dictionary_create_empty();
	ASSERT_NOT_NULL(dict);
	ASSERT_EQUAL_U(0, xpc_dictionary_get_count(dict));
	xpc_release(dict);
};

CTEST(dictionary, create_nonempty) {
	const char* keys[OBJECT_COUNT];
	xpc_object_t objects[OBJECT_COUNT];
	create_keys(keys, OBJECT_COUNT);
	create_objects(objects, OBJECT_COUNT);
	xpc_object_t dict = xpc_dictionary_create(keys, objects, OBJECT_COUNT);

	ASSERT_NOT_NULL(dict);
	ASSERT_EQUAL_U(OBJECT_COUNT, xpc_dictionary_get_count(dict));
	for (size_t i = 0; i < OBJECT_COUNT; ++i) {
		// we have a reference but the dictionary should have one too
		NSUInteger retainCount = [objects[i] retainCount];
		// global objects have NSUIntegerMax as their reference count
		if (retainCount != NSUIntegerMax) {
			ASSERT_EQUAL_U(2, retainCount);
		}
	}

	xpc_release(dict);

	for (size_t i = 0; i < OBJECT_COUNT; ++i) {
		// we should have the only reference now
		NSUInteger retainCount = [objects[i] retainCount];
		if (retainCount != NSUIntegerMax) {
			ASSERT_EQUAL_U(1, retainCount);
		}
	}

	release_objects(objects, OBJECT_COUNT);
	release_keys(keys, OBJECT_COUNT);
};

CTEST2(dictionary, get_value) {
	size_t index = rand_index(OBJECT_COUNT);
	ASSERT_EQUAL_PTR(data->objects[index], xpc_dictionary_get_value(data->dict, data->keys[index]));
};

CTEST2(dictionary, set_value) {
	xpc_object_t newObject = xpc_int64_create(10);
	NSUInteger oldRefCount = 0;
	size_t index = rand_index(OBJECT_COUNT);

	xpc_dictionary_set_value(data->dict, data->keys[index], newObject);
	// setting the new value at that index should have dropped the old value
	oldRefCount = [data->objects[index] retainCount];
	if (oldRefCount != NSUIntegerMax) {
		ASSERT_EQUAL_U(1, [data->objects[index] retainCount]);
	}
	// and it should have assigned and retained the new value
	ASSERT_EQUAL_PTR(newObject, xpc_dictionary_get_value(data->dict, data->keys[index]));
	ASSERT_EQUAL_U(2, [newObject retainCount]);

	xpc_release(newObject);
};

CTEST2(dictionary, add_value) {
	xpc_object_t newObject = xpc_int64_create(10);
	xpc_object_t newObject2 = xpc_int64_create(15);

	xpc_dictionary_set_value(data->dict, "some random key", newObject);
	ASSERT_EQUAL_U(OBJECT_COUNT + 1, xpc_dictionary_get_count(data->dict));
	ASSERT_EQUAL_PTR(newObject, xpc_dictionary_get_value(data->dict, "some random key"));

	xpc_release(newObject);
};

static void visitor(const char* key, xpc_object_t value, void* context) {
	size_t* visitedCount = context;
	++*visitedCount;
};

CTEST2(dictionary, apply) {
	__block size_t visitedCount = 0;
	const char* key = rand_key(data->keys, OBJECT_COUNT);

	xpc_dictionary_apply(data->dict, ^bool(const char* key, xpc_object_t value) {
		++visitedCount;
		return true;
	});
	ASSERT_EQUAL_U(OBJECT_COUNT, visitedCount);

	// i'm not sure how to test the early stop with dictionaries, so for now, we won't

	visitedCount = 0;
	xpc_dictionary_apply_f(data->dict, &visitedCount, visitor);
	ASSERT_EQUAL_U(OBJECT_COUNT, visitedCount);
};

// like arrays, dictionaries have too many getters and setters and i don't want to write tests for all of them
//
// if the basic API works, everything should work
// (all the getters and setters use the basic API to do their stuff)
