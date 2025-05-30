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

#include <string.h> // memcmp, memcpy
#include <stdlib.h> // malloc, free

#include "reefnet_sensus.h"
#include "context-private.h"
#include "device-private.h"
#include "checksum.h"
#include "array.h"

#define ISINSTANCE(device) dc_device_isinstance((device), &reefnet_sensus_device_vtable)

#define SZ_MEMORY    32768
#define SZ_HANDSHAKE 10

typedef struct reefnet_sensus_device_t {
	dc_device_t base;
	dc_iostream_t *iostream;
	unsigned char handshake[SZ_HANDSHAKE];
	unsigned int waiting;
	unsigned int timestamp;
	unsigned int devtime;
	dc_ticks_t systime;
} reefnet_sensus_device_t;

static dc_status_t reefnet_sensus_device_set_fingerprint (dc_device_t *abstract, const unsigned char data[], unsigned int size);
static dc_status_t reefnet_sensus_device_dump (dc_device_t *abstract, dc_buffer_t *buffer);
static dc_status_t reefnet_sensus_device_foreach (dc_device_t *abstract, dc_dive_callback_t callback, void *userdata);
static dc_status_t reefnet_sensus_device_close (dc_device_t *abstract);

static const dc_device_vtable_t reefnet_sensus_device_vtable = {
	sizeof(reefnet_sensus_device_t),
	DC_FAMILY_REEFNET_SENSUS,
	reefnet_sensus_device_set_fingerprint, /* set_fingerprint */
	NULL, /* read */
	NULL, /* write */
	reefnet_sensus_device_dump, /* dump */
	reefnet_sensus_device_foreach, /* foreach */
	NULL, /* timesync */
	reefnet_sensus_device_close /* close */
};

static dc_status_t
reefnet_sensus_extract_dives (dc_device_t *device, const unsigned char data[], unsigned int size, dc_dive_callback_t callback, void *userdata);

static dc_status_t
reefnet_sensus_cancel (reefnet_sensus_device_t *device)
{
	dc_status_t status = DC_STATUS_SUCCESS;
	dc_device_t *abstract = (dc_device_t *) device;

	// Send the command to the device.
	unsigned char command = 0x00;
	status = dc_iostream_write (device->iostream, &command, 1, NULL);
	if (status != DC_STATUS_SUCCESS) {
		ERROR (abstract->context, "Failed to send the command.");
		return status;
	}

	// The device leaves the waiting state.
	device->waiting = 0;

	return DC_STATUS_SUCCESS;
}


dc_status_t
reefnet_sensus_device_open (dc_device_t **out, dc_context_t *context, dc_iostream_t *iostream)
{
	dc_status_t status = DC_STATUS_SUCCESS;
	reefnet_sensus_device_t *device = NULL;

	if (out == NULL)
		return DC_STATUS_INVALIDARGS;

	// Allocate memory.
	device = (reefnet_sensus_device_t *) dc_device_allocate (context, &reefnet_sensus_device_vtable);
	if (device == NULL) {
		ERROR (context, "Failed to allocate memory.");
		return DC_STATUS_NOMEMORY;
	}

	// Set the default values.
	device->iostream = iostream;
	device->waiting = 0;
	device->timestamp = 0;
	device->systime = (dc_ticks_t) -1;
	device->devtime = 0;
	memset (device->handshake, 0, sizeof (device->handshake));

	// Set the serial communication protocol (19200 8N1).
	status = dc_iostream_configure (device->iostream, 19200, 8, DC_PARITY_NONE, DC_STOPBITS_ONE, DC_FLOWCONTROL_NONE);
	if (status != DC_STATUS_SUCCESS) {
		ERROR (context, "Failed to set the terminal attributes.");
		goto error_free;
	}

	// Set the timeout for receiving data (3000 ms).
	status = dc_iostream_set_timeout (device->iostream, 3000);
	if (status != DC_STATUS_SUCCESS) {
		ERROR (context, "Failed to set the timeout.");
		goto error_free;
	}

	// Make sure everything is in a sane state.
	dc_iostream_purge (device->iostream, DC_DIRECTION_ALL);

	*out = (dc_device_t*) device;

	return DC_STATUS_SUCCESS;

error_free:
	dc_device_deallocate ((dc_device_t *) device);
	return status;
}


static dc_status_t
reefnet_sensus_device_close (dc_device_t *abstract)
{
	dc_status_t status = DC_STATUS_SUCCESS;
	reefnet_sensus_device_t *device = (reefnet_sensus_device_t*) abstract;
	dc_status_t rc = DC_STATUS_SUCCESS;

	// Safely close the connection if the last handshake was
	// successful, but no data transfer was ever initiated.
	if (device->waiting) {
		rc = reefnet_sensus_cancel (device);
		if (rc != DC_STATUS_SUCCESS) {
			dc_status_set_error(&status, rc);
		}
	}

	return status;
}


dc_status_t
reefnet_sensus_device_get_handshake (dc_device_t *abstract, unsigned char data[], unsigned int size)
{
	reefnet_sensus_device_t *device = (reefnet_sensus_device_t*) abstract;

	if (!ISINSTANCE (abstract))
		return DC_STATUS_INVALIDARGS;

	if (size < SZ_HANDSHAKE) {
		ERROR (abstract->context, "Insufficient buffer space available.");
		return DC_STATUS_INVALIDARGS;
	}

	memcpy (data, device->handshake, SZ_HANDSHAKE);

	return DC_STATUS_SUCCESS;
}


static dc_status_t
reefnet_sensus_device_set_fingerprint (dc_device_t *abstract, const unsigned char data[], unsigned int size)
{
	reefnet_sensus_device_t *device = (reefnet_sensus_device_t*) abstract;

	if (size && size != 4)
		return DC_STATUS_INVALIDARGS;

	if (size)
		device->timestamp = array_uint32_le (data);
	else
		device->timestamp = 0;

	return DC_STATUS_SUCCESS;
}


static dc_status_t
reefnet_sensus_handshake (reefnet_sensus_device_t *device)
{
	dc_status_t status = DC_STATUS_SUCCESS;
	dc_device_t *abstract = (dc_device_t *) device;

	// Send the command to the device.
	unsigned char command = 0x0A;
	status = dc_iostream_write (device->iostream, &command, 1, NULL);
	if (status != DC_STATUS_SUCCESS) {
		ERROR (abstract->context, "Failed to send the command.");
		return status;
	}

	// Receive the answer from the device.
	unsigned char handshake[SZ_HANDSHAKE + 2] = {0};
	status = dc_iostream_read (device->iostream, handshake, sizeof (handshake), NULL);
	if (status != DC_STATUS_SUCCESS) {
		ERROR (abstract->context, "Failed to receive the handshake.");
		return status;
	}

	// Verify the header of the packet.
	if (handshake[0] != 'O' || handshake[1] != 'K') {
		ERROR (abstract->context, "Unexpected answer header.");
		return DC_STATUS_PROTOCOL;
	}

	HEXDUMP (abstract->context, DC_LOGLEVEL_DEBUG, "Handshake", handshake + 2, sizeof(handshake) - 2);

	// The device is now waiting for a data request.
	device->waiting = 1;

	// Store the clock calibration values.
	device->systime = dc_datetime_now ();
	device->devtime = array_uint32_le (handshake + 8);

	// Store the handshake packet.
	memcpy (device->handshake, handshake + 2, SZ_HANDSHAKE);

	// Emit a clock event.
	dc_event_clock_t clock;
	clock.systime = device->systime;
	clock.devtime = device->devtime;
	device_event_emit (&device->base, DC_EVENT_CLOCK, &clock);

	// Emit a device info event.
	dc_event_devinfo_t devinfo;
	devinfo.model = handshake[2] - '0';
	devinfo.firmware = handshake[3] - '0';
	devinfo.serial = array_uint16_le (handshake + 6);
	device_event_emit (&device->base, DC_EVENT_DEVINFO, &devinfo);

	// Emit a vendor event.
	dc_event_vendor_t vendor;
	vendor.data = device->handshake;
	vendor.size = sizeof (device->handshake);
	device_event_emit (abstract, DC_EVENT_VENDOR, &vendor);

	// Wait at least 10 ms to ensures the data line is
	// clear before transmission from the host begins.

	dc_iostream_sleep (device->iostream, 10);

	return DC_STATUS_SUCCESS;
}


static dc_status_t
reefnet_sensus_device_dump (dc_device_t *abstract, dc_buffer_t *buffer)
{
	dc_status_t status = DC_STATUS_SUCCESS;
	reefnet_sensus_device_t *device = (reefnet_sensus_device_t*) abstract;

	// Pre-allocate the required amount of memory.
	if (!dc_buffer_reserve (buffer, SZ_MEMORY)) {
		ERROR (abstract->context, "Insufficient buffer space available.");
		return DC_STATUS_NOMEMORY;
	}

	// Enable progress notifications.
	dc_event_progress_t progress = EVENT_PROGRESS_INITIALIZER;
	progress.maximum = 4 + SZ_MEMORY + 2 + 3;
	device_event_emit (abstract, DC_EVENT_PROGRESS, &progress);

	// Wake-up the device.
	dc_status_t rc = reefnet_sensus_handshake (device);
	if (rc != DC_STATUS_SUCCESS)
		return rc;

	// Send the command to the device.
	unsigned char command = 0x40;
	status = dc_iostream_write (device->iostream, &command, 1, NULL);
	if (status != DC_STATUS_SUCCESS) {
		ERROR (abstract->context, "Failed to send the command.");
		return status;
	}

	// The device leaves the waiting state.
	device->waiting = 0;

	// Receive the answer from the device.
	unsigned int nbytes = 0;
	unsigned char answer[4 + SZ_MEMORY + 2 + 3] = {0};
	while (nbytes < sizeof (answer)) {
		unsigned int len = sizeof (answer) - nbytes;
		if (len > 128)
			len = 128;

		status = dc_iostream_read (device->iostream, answer + nbytes, len, NULL);
		if (status != DC_STATUS_SUCCESS) {
			ERROR (abstract->context, "Failed to receive the answer.");
			return status;
		}

		// Update and emit a progress event.
		progress.current += len;
		device_event_emit (abstract, DC_EVENT_PROGRESS, &progress);

		nbytes += len;
	}

	// Verify the headers of the package.
	if (memcmp (answer, "DATA", 4) != 0 ||
		memcmp (answer + sizeof (answer) - 3, "END", 3) != 0) {
		ERROR (abstract->context, "Unexpected answer start or end byte(s).");
		return DC_STATUS_PROTOCOL;
	}

	// Verify the checksum of the package.
	unsigned short crc = array_uint16_le (answer + 4 + SZ_MEMORY);
	unsigned short ccrc = checksum_add_uint16 (answer + 4, SZ_MEMORY, 0x00);
	if (crc != ccrc) {
		ERROR (abstract->context, "Unexpected answer checksum.");
		return DC_STATUS_PROTOCOL;
	}

	dc_buffer_append (buffer, answer + 4, SZ_MEMORY);

	return DC_STATUS_SUCCESS;
}


static dc_status_t
reefnet_sensus_device_foreach (dc_device_t *abstract, dc_dive_callback_t callback, void *userdata)
{
	dc_buffer_t *buffer = dc_buffer_new (SZ_MEMORY);
	if (buffer == NULL)
		return DC_STATUS_NOMEMORY;

	dc_status_t rc = reefnet_sensus_device_dump (abstract, buffer);
	if (rc != DC_STATUS_SUCCESS) {
		dc_buffer_free (buffer);
		return rc;
	}

	rc = reefnet_sensus_extract_dives (abstract,
		dc_buffer_get_data (buffer), dc_buffer_get_size (buffer), callback, userdata);

	dc_buffer_free (buffer);

	return rc;
}


static dc_status_t
reefnet_sensus_extract_dives (dc_device_t *abstract, const unsigned char data[], unsigned int size, dc_dive_callback_t callback, void *userdata)
{
	reefnet_sensus_device_t *device = (reefnet_sensus_device_t*) abstract;
	dc_context_t *context = (abstract ? abstract->context : NULL);

	if (abstract && !ISINSTANCE (abstract))
		return DC_STATUS_INVALIDARGS;

	// Search the entire data stream for start markers.
	unsigned int previous = size;
	unsigned int current = (size >= 7 ? size - 7 : 0);
	while (current > 0) {
		current--;
		if (data[current] == 0xFF && data[current + 6] == 0xFE) {
			// Once a start marker is found, start searching
			// for the end of the dive. The search is now
			// limited to the start of the previous dive.
			int found = 0;
			unsigned int nsamples = 0, count = 0;
			unsigned int offset = current + 7; // Skip non-sample data.
			while (offset + 1 <= previous) {
				// Depth (adjusted feet of seawater).
				unsigned char depth = data[offset++];

				// Temperature (degrees Fahrenheit)
				if ((nsamples % 6) == 0) {
					if (offset + 1 > previous)
						break;
					offset++;
				}

				// Current sample is complete.
				nsamples++;

				// The end of a dive is reached when 17 consecutive
				// depth samples of less than 3 feet have been found.
				if (depth < 13 + 3) {
					count++;
					if (count == 17) {
						found = 1;
						break;
					}
				} else {
					count = 0;
				}
			}

			// Report an error if no end of dive was found.
			if (!found) {
				ERROR (context, "No end of dive found.");
				return DC_STATUS_DATAFORMAT;
			}

			// Automatically abort when a dive is older than the provided timestamp.
			unsigned int timestamp = array_uint32_le (data + current + 2);
			if (device && timestamp <= device->timestamp)
				return DC_STATUS_SUCCESS;

			if (callback && !callback (data + current, offset - current, data + current + 2, 4, userdata))
				return DC_STATUS_SUCCESS;

			// Prepare for the next dive.
			previous = current;
			current = (current >= 7 ? current - 7 : 0);
		}
	}

	return DC_STATUS_SUCCESS;
}