#include "configuredc.h"
#include "libdivecomputer/common.h"
#include "libdivecomputer/iostream.h"
#include "libdivecomputer/custom.h"
#include "iostream-private.h"
#include "libdivecomputer/context.h"
#include "suunto_eonsteel.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "BLEBridge.h"

static dc_status_t ble_set_timeout_wrapper(void *io, int timeout) {
    return ble_set_timeout((ble_object_t *)io, timeout);
}

static dc_status_t ble_read_wrapper(void *io, void *data, size_t size, size_t *actual) {
    return ble_read((ble_object_t *)io, data, size, actual);
}

static dc_status_t ble_write_wrapper(void *io, const void *data, size_t size, size_t *actual) {
    return ble_write((ble_object_t *)io, data, size, actual);
}

static dc_status_t ble_ioctl_wrapper(void *io, unsigned int request, void *data, size_t size) {
    return ble_ioctl((ble_object_t *)io, request, data, size);
}

static dc_status_t ble_sleep_wrapper(void *io, unsigned int milliseconds) {
    return ble_sleep((ble_object_t *)io, milliseconds);
}

static dc_status_t ble_close_wrapper(void *io) {
    return ble_close((ble_object_t *)io);
}

dc_status_t
ble_packet_open(dc_iostream_t **iostream, dc_context_t *context, const char* devaddr, void *userdata)
{
    ble_object_t *io = NULL;

    static const dc_custom_cbs_t callbacks = {
        .set_timeout = ble_set_timeout_wrapper,
        .set_break   = NULL,
        .set_dtr     = NULL,
        .set_rts     = NULL,
        .get_lines   = NULL,
        .get_available = NULL,
        .configure   = NULL,
        .poll        = NULL,
        .read        = ble_read_wrapper,
        .write       = ble_write_wrapper,
        .ioctl       = ble_ioctl_wrapper,
        .flush       = NULL,
        .purge       = NULL,
        .sleep       = ble_sleep_wrapper,
        .close       = ble_close_wrapper,
    };

    // Initialize BLE manager
    initializeBLEManager();

    // Create a BLE object
    io = createBLEObject();
    if (io == NULL) {
        return DC_STATUS_NOMEMORY;
    }

    // Connect to the device
    if (!connectToBLEDevice(io, devaddr)) {
        freeBLEObject(io);
        return DC_STATUS_IO;
    }

    // Discover services
    if (!discoverServices(io)) {
        freeBLEObject(io);
        return DC_STATUS_IO;
    }

    // Enable notifications
    if (!enableNotifications(io)) {
        freeBLEObject(io);
        return DC_STATUS_IO;
    }

    // If all operations succeed, return success
    return dc_custom_open(iostream, context, DC_TRANSPORT_BLE, &callbacks, io);
}

dc_status_t open_suunto_eonsteel(device_data_t *data, const char *devaddr) {
    dc_status_t rc = DC_STATUS_SUCCESS;
    data->device = NULL;
    data->context = NULL;
    data->iostream = NULL;
    unsigned int model = 2;  // Suunto D5 model number
    
    rc = dc_context_new(&data->context);
    if (rc != DC_STATUS_SUCCESS) {
        printf("Failed to create libdc context\n");
        return rc;
    }
    
    // Open BLE connection
    rc = ble_packet_open(&data->iostream, data->context, devaddr, data);
    if (rc != DC_STATUS_SUCCESS) {
        printf("Failed to open BLE connection\n");
        dc_context_free(data->context);
        return rc;
    }
    
    rc = suunto_eonsteel_device_open(&data->device, data->context, data->iostream, model);
    if (rc != DC_STATUS_SUCCESS) {
        printf("Failed to open Suunto EON Steel device\n");
        dc_iostream_close(data->iostream);
        dc_context_free(data->context);
        return rc;
    }
    
    return rc;
}
