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

#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "suunto_eon.h"
#include "suunto_eonsteel.h"
#include "suunto_solution.h"
#include "device-private.h"
#include "context-private.h"

dc_device_t *
dc_device_allocate (dc_context_t *context, const dc_device_vtable_t *vtable)
{
	dc_device_t *device = NULL;

	assert(vtable != NULL);
	assert(vtable->size >= sizeof(dc_device_t));

	// Allocate memory.
	device = (dc_device_t *) malloc (vtable->size);
	if (device == NULL) {
		ERROR (context, "Failed to allocate memory.");
		return device;
	}

	device->vtable = vtable;

	device->context = context;

	device->event_mask = 0;
	device->event_callback = NULL;
	device->event_userdata = NULL;

	device->cancel_callback = NULL;
	device->cancel_userdata = NULL;

	memset (&device->devinfo, 0, sizeof (device->devinfo));
	memset (&device->clock, 0, sizeof (device->clock));

	return device;
}

void
dc_device_deallocate (dc_device_t *device)
{
	free (device);
}

dc_status_t
dc_device_open (dc_device_t **out, dc_context_t *context, dc_descriptor_t *descriptor, dc_iostream_t *iostream)
{
	dc_status_t rc = DC_STATUS_SUCCESS;
	dc_device_t *device = NULL;

	if (out == NULL || descriptor == NULL)
		return DC_STATUS_INVALIDARGS;

	switch (dc_descriptor_get_type (descriptor)) {
	case DC_FAMILY_SUUNTO_SOLUTION:
		rc = suunto_solution_device_open (&device, context, iostream);
		break;
	case DC_FAMILY_SUUNTO_EON:
		rc = suunto_eon_device_open (&device, context, iostream);
		break;
	case DC_FAMILY_SUUNTO_EONSTEEL:
		rc = suunto_eonsteel_device_open (&device, context, iostream, dc_descriptor_get_model (descriptor));
		break;
	default:
		return DC_STATUS_INVALIDARGS;
	}

	*out = device;

	return rc;
}


int
dc_device_isinstance (dc_device_t *device, const dc_device_vtable_t *vtable)
{
	if (device == NULL)
		return 0;

	return device->vtable == vtable;
}


dc_family_t
dc_device_get_type (dc_device_t *device)
{
	if (device == NULL)
		return DC_FAMILY_NULL;

	return device->vtable->type;
}


dc_status_t
dc_device_set_cancel (dc_device_t *device, dc_cancel_callback_t callback, void *userdata)
{
	if (device == NULL)
		return DC_STATUS_UNSUPPORTED;

	device->cancel_callback = callback;
	device->cancel_userdata = userdata;

	return DC_STATUS_SUCCESS;
}


dc_status_t
dc_device_set_events (dc_device_t *device, unsigned int events, dc_event_callback_t callback, void *userdata)
{
	if (device == NULL)
		return DC_STATUS_UNSUPPORTED;

	device->event_mask = events;
	device->event_callback = callback;
	device->event_userdata = userdata;

	return DC_STATUS_SUCCESS;
}


dc_status_t
dc_device_set_fingerprint (dc_device_t *device, const unsigned char data[], unsigned int size)
{
	if (device == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (device->vtable->set_fingerprint == NULL)
		return DC_STATUS_UNSUPPORTED;

	return device->vtable->set_fingerprint (device, data, size);
}


dc_status_t
dc_device_read (dc_device_t *device, unsigned int address, unsigned char data[], unsigned int size)
{
	if (device == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (device->vtable->read == NULL)
		return DC_STATUS_UNSUPPORTED;

	return device->vtable->read (device, address, data, size);
}


dc_status_t
dc_device_write (dc_device_t *device, unsigned int address, const unsigned char data[], unsigned int size)
{
	if (device == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (device->vtable->write == NULL)
		return DC_STATUS_UNSUPPORTED;

	return device->vtable->write (device, address, data, size);
}


dc_status_t
dc_device_dump (dc_device_t *device, dc_buffer_t *buffer)
{
	if (device == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (device->vtable->dump == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (buffer == NULL)
		return DC_STATUS_INVALIDARGS;

	dc_buffer_clear (buffer);

	return device->vtable->dump (device, buffer);
}


dc_status_t
device_dump_read (dc_device_t *device, unsigned int address, unsigned char data[], unsigned int size, unsigned int blocksize)
{
	if (device == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (device->vtable->read == NULL)
		return DC_STATUS_UNSUPPORTED;

	// Enable progress notifications.
	dc_event_progress_t progress = EVENT_PROGRESS_INITIALIZER;
	progress.maximum = size;
	device_event_emit (device, DC_EVENT_PROGRESS, &progress);

	unsigned int nbytes = 0;
	while (nbytes < size) {
		// Calculate the packet size.
		unsigned int len = size - nbytes;
		if (len > blocksize)
			len = blocksize;

		// Read the packet.
		dc_status_t rc = device->vtable->read (device, address + nbytes, data + nbytes, len);
		if (rc != DC_STATUS_SUCCESS)
			return rc;

		// Update and emit a progress event.
		progress.current += len;
		device_event_emit (device, DC_EVENT_PROGRESS, &progress);

		nbytes += len;
	}

	return DC_STATUS_SUCCESS;
}


dc_status_t
dc_device_foreach (dc_device_t *device, dc_dive_callback_t callback, void *userdata)
{
	if (device == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (device->vtable->foreach == NULL)
		return DC_STATUS_UNSUPPORTED;

	return device->vtable->foreach (device, callback, userdata);
}


dc_status_t
dc_device_timesync (dc_device_t *device, const dc_datetime_t *datetime)
{
	if (device == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (device->vtable->timesync == NULL)
		return DC_STATUS_UNSUPPORTED;

	if (datetime == NULL)
		return DC_STATUS_INVALIDARGS;

	return device->vtable->timesync (device, datetime);
}


dc_status_t
dc_device_close (dc_device_t *device)
{
	dc_status_t status = DC_STATUS_SUCCESS;

	if (device == NULL)
		return DC_STATUS_SUCCESS;

	// Disable the cancellation callback.
	device->cancel_callback = NULL;
	device->cancel_userdata = NULL;

	if (device->vtable->close) {
		status = device->vtable->close (device);
	}

	dc_device_deallocate (device);

	return status;
}


void
device_event_emit (dc_device_t *device, dc_event_type_t event, const void *data)
{
	const dc_event_progress_t *progress = (const dc_event_progress_t *) data;

	// Check the event data for errors.
	switch (event) {
	case DC_EVENT_WAITING:
		assert (data == NULL);
		break;
	case DC_EVENT_PROGRESS:
		assert (progress != NULL);
		assert (progress->maximum != 0);
		assert (progress->maximum >= progress->current);
		break;
	case DC_EVENT_DEVINFO:
		assert (data != NULL);
		break;
	case DC_EVENT_CLOCK:
		assert (data != NULL);
		break;
	default:
		break;
	}

	if (device == NULL)
		return;

	// Cache the event data.
	switch (event) {
	case DC_EVENT_DEVINFO:
		device->devinfo = *(const dc_event_devinfo_t *) data;
		break;
	case DC_EVENT_CLOCK:
		device->clock = *(const dc_event_clock_t *) data;
		break;
	default:
		break;
	}

	// Check if there is a callback function registered.
	if (device->event_callback == NULL)
		return;

	// Check the event mask.
	if ((event & device->event_mask) == 0)
		return;

	device->event_callback (device, event, data, device->event_userdata);
}


int
device_is_cancelled (dc_device_t *device)
{
	if (device == NULL)
		return 0;

	if (device->cancel_callback == NULL)
		return 0;

	return device->cancel_callback (device->cancel_userdata);
}
