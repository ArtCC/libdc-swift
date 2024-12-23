#include "configuredc.h"
#include "BLEBridge.h"
#include <libdivecomputer/device.h>
#include <libdivecomputer/descriptor.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static void event_cb(dc_device_t *device, dc_event_type_t event, const void *data, void *userdata)
{
    device_data_t *devdata = (device_data_t *)userdata;
    if (!devdata) return;
    
    switch (event) {
    case DC_EVENT_DEVINFO:
        {
            const dc_event_devinfo_t *devinfo = (const dc_event_devinfo_t *)data;
            devdata->devinfo = *devinfo;
            devdata->have_devinfo = 1;
        }
        break;
    case DC_EVENT_PROGRESS:
        {
            const dc_event_progress_t *progress = (const dc_event_progress_t *)data;
            devdata->progress = *progress;
            devdata->have_progress = 1;
        }
        break;
    case DC_EVENT_CLOCK:
        {
            const dc_event_clock_t *clock = (const dc_event_clock_t *)data;
            devdata->clock = *clock;
            devdata->have_clock = 1;
        }
        break;
    default:
        break;
    }
}

static void close_device_data(device_data_t *data) {
    if (!data) return;
            
    if (data->device) {
        dc_device_close(data->device);
        data->device = NULL;
    }
    if (data->iostream) {
        dc_iostream_close(data->iostream);
        data->iostream = NULL;
    }
    if (data->context) {
        dc_context_free(data->context);
        data->context = NULL;
    }
}

dc_status_t open_ble_device_with_descriptor(device_data_t *data, const char *devaddr, dc_descriptor_t *descriptor) {
    dc_status_t rc;
    
    if (!data || !devaddr || !descriptor) {
        return DC_STATUS_INVALIDARGS;
    }

    // Initialize all pointers to NULL
    memset(data, 0, sizeof(device_data_t));
    
    // Create context
    rc = dc_context_new(&data->context);
    if (rc != DC_STATUS_SUCCESS) {
        printf("Failed to create context, rc=%d\n", rc);
        return rc;
    }

    // Create BLE iostream
    rc = ble_packet_open(&data->iostream, data->context, devaddr, data);
    if (rc != DC_STATUS_SUCCESS) {
        printf("Failed to open BLE connection, rc=%d\n", rc);
        close_device_data(data);
        return rc;
    }

    // Use dc_device_open to handle device-specific opening
    rc = dc_device_open(&data->device, data->context, descriptor, data->iostream);
    if (rc != DC_STATUS_SUCCESS) {
        printf("Failed to open device, rc=%d\n", rc);
        close_device_data(data);
        return rc;
    }

    // Set up event handler
    unsigned int events = DC_EVENT_DEVINFO | DC_EVENT_PROGRESS | DC_EVENT_CLOCK;
    rc = dc_device_set_events(data->device, events, event_cb, data);
    if (rc != DC_STATUS_SUCCESS) {
        printf("Failed to set event handler, rc=%d\n", rc);
        close_device_data(data);
        return rc;
    }

    return rc;
}

dc_status_t identify_ble_device(const char* name, dc_family_t* family, unsigned int* model) {
    dc_status_t rc = DC_STATUS_SUCCESS;
    dc_iterator_t *iterator = NULL;
    dc_descriptor_t *descriptor = NULL;

    rc = dc_descriptor_iterator(&iterator);
    if (rc != DC_STATUS_SUCCESS) {
        return rc;
    }

    while ((rc = dc_iterator_next(iterator, &descriptor)) == DC_STATUS_SUCCESS) {
        const char *product = dc_descriptor_get_product(descriptor);
        if (product && strstr(name, product) != NULL) {
            *family = dc_descriptor_get_type(descriptor);
            *model = dc_descriptor_get_model(descriptor);
            dc_descriptor_free(descriptor);
            dc_iterator_free(iterator);
            return DC_STATUS_SUCCESS;
        }
        dc_descriptor_free(descriptor);
    }

    dc_iterator_free(iterator);
    return DC_STATUS_UNSUPPORTED;
} 