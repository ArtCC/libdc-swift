/*
 * libdivecomputer
 *
 * Copyright (C) 2008 Jef Driesen
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301 USA
 */

#include <stdlib.h>
#include <assert.h>
#include "suunto_eon.h"
#include "suunto_eonsteel.h"
#include "suunto_solution.h"
#include "context-private.h"
#include "parser-private.h"
#include "device-private.h"

#define REACTPROWHITE 0x4354

// Creates a new parser based on the device family and model
static dc_status_t
dc_parser_new_internal (dc_parser_t **out, dc_context_t *context, dc_family_t family, unsigned int model, unsigned int devtime, dc_ticks_t systime)
{
	dc_status_t rc = DC_STATUS_SUCCESS;
	dc_parser_t *parser = NULL;

	if (out == NULL)
		return DC_STATUS_INVALIDARGS;
    // ... (switch statement to create the appropriate parser based on family and model)
	switch (family) {
	case DC_FAMILY_SUUNTO_SOLUTION:
		rc = suunto_solution_parser_create (&parser, context);
		break;
	case DC_FAMILY_SUUNTO_EON:
		rc = suunto_eon_parser_create (&parser, context, 0);
		break;
	case DC_FAMILY_SUUNTO_EONSTEEL:
		rc = suunto_eonsteel_parser_create(&parser, context, model);
		break;
	default:
		return DC_STATUS_INVALIDARGS;
	}

	*out = parser;

	return rc;
}

/* MARK - There are two ways to create a parser: 1. from device information, 2. from a descriptor */
// Creates a new parser from a device information
dc_status_t
dc_parser_new (dc_parser_t **out, dc_device_t *device)
{
	if (device == NULL)
		return DC_STATUS_INVALIDARGS;
    
    // Calls a dc_parser_new_internal with device information
	return dc_parser_new_internal (out, device->context,
		dc_device_get_type (device), device->devinfo.model,
		device->clock.devtime, device->clock.systime);
}

// Creates a new parser from a descriptor
dc_status_t
dc_parser_new2 (dc_parser_t **out, dc_context_t *context, dc_descriptor_t *descriptor, unsigned int devtime, dc_ticks_t systime)
{
    // Calls a dc_parser_new_internal with descriptor information
	return dc_parser_new_internal (out, context,
		dc_descriptor_get_type (descriptor), dc_descriptor_get_model (descriptor),
		devtime, systime);
}

// Allocates a memory for a parser and initializes its base class
dc_parser_t *
dc_parser_allocate (dc_context_t *context, const dc_parser_vtable_t *vtable)
{
	dc_parser_t *parser = NULL;

	assert(vtable != NULL);
	assert(vtable->size >= sizeof(dc_parser_t));

	// Allocate memory.
	parser = (dc_parser_t *) malloc (vtable->size);
	if (parser == NULL) {
		ERROR (context, "Failed to allocate memory.");
		return parser;
	}

	// Initialize the base class.
	parser->vtable = vtable;
	parser->context = context;
	parser->data = NULL;
	parser->size = 0;

	return parser;
}

// Frees the memory allocated for a parser
void
dc_parser_deallocate (dc_parser_t *parser)
{
    // Frees the parser memory
	free (parser);
}

// Check if a parser is an instance of a specific type
int
dc_parser_isinstance (dc_parser_t *parser, const dc_parser_vtable_t *vtable)
{
	if (parser == NULL)
		return 0;

	return parser->vtable == vtable;
}

// Gets the type of the parser
dc_family_t
dc_parser_get_type (dc_parser_t *parser)
{
    // Returns the parser type from its vtable
	if (parser == NULL)
		return DC_FAMILY_NULL;

	return parser->vtable->type;
}

// Set the clock for a parser
dc_status_t
dc_parser_set_clock (dc_parser_t *parser, unsigned int devtime, dc_ticks_t systime)
{
	if (parser == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (parser->vtable->set_clock == NULL)
		return DC_STATUS_UNSUPPORTED;

	return parser->vtable->set_clock (parser, devtime, systime);
}

// Sets atmospheric pressure for the parser
dc_status_t
dc_parser_set_atmospheric (dc_parser_t *parser, double atmospheric)
{
	if (parser == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (parser->vtable->set_atmospheric == NULL)
		return DC_STATUS_UNSUPPORTED;

	return parser->vtable->set_atmospheric (parser, atmospheric);
}

// Sets the water density of a parser
dc_status_t
dc_parser_set_density (dc_parser_t *parser, double density)
{
	if (parser == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (parser->vtable->set_density == NULL)
		return DC_STATUS_UNSUPPORTED;

	return parser->vtable->set_density (parser, density);
}

// Sets the dive data for the parser to work with
dc_status_t
dc_parser_set_data (dc_parser_t *parser, const unsigned char *data, unsigned int size)
{
	if (parser == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (parser->vtable->set_data == NULL)
		return DC_STATUS_UNSUPPORTED;

	parser->data = data;
	parser->size = size;

	return parser->vtable->set_data (parser, data, size);
}

// Gets the date and time of the dive
dc_status_t
dc_parser_get_datetime (dc_parser_t *parser, dc_datetime_t *datetime)
{
	if (parser == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (parser->vtable->datetime == NULL)
		return DC_STATUS_UNSUPPORTED;
    
    // Calls the parser's datetime function if available
	return parser->vtable->datetime (parser, datetime);
}

// Gets a specific field from the parsed data
dc_status_t
dc_parser_get_field (dc_parser_t *parser, dc_field_type_t type, unsigned int flags, void *value)
{
	if (parser == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (parser->vtable->field == NULL)
		return DC_STATUS_UNSUPPORTED;

	return parser->vtable->field (parser, type, flags, value);
}

// Iterates through all samples in the dive data
dc_status_t
dc_parser_samples_foreach (dc_parser_t *parser, dc_sample_callback_t callback, void *userdata)
{
	if (parser == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (parser->vtable->samples_foreach == NULL)
		return DC_STATUS_UNSUPPORTED;

	return parser->vtable->samples_foreach (parser, callback, userdata);
}

// Destroys the parser and free its resources
dc_status_t
dc_parser_destroy (dc_parser_t *parser)
{
	dc_status_t status = DC_STATUS_SUCCESS;

	if (parser == NULL)
		return DC_STATUS_SUCCESS;

	if (parser->vtable->destroy) {
		status = parser->vtable->destroy (parser);
	}

	dc_parser_deallocate (parser);

	return status;
}

// Callback function to calculate dive statistics
void
sample_statistics_cb (dc_sample_type_t type, dc_sample_value_t value, void *userdata)
{
	sample_statistics_t *statistics  = (sample_statistics_t *) userdata;
    
    // Updates dive statistics based on sample data
	switch (type) {
	case DC_SAMPLE_TIME:
		statistics->divetime = value.time;
		break;
	case DC_SAMPLE_DEPTH:
		if (statistics->maxdepth < value.depth)
			statistics->maxdepth = value.depth;
		break;
	default:
		break;
	}
}
