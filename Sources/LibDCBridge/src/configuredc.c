#include "configuredc.h"
#include "BLEBridge.h"
#include <libdivecomputer/device.h>
#include <libdivecomputer/descriptor.h>
#include <libdivecomputer/iostream.h>
#include "iostream-private.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/*--------------------------------------------------------------------
 * BLE stream structures
 *------------------------------------------------------------------*/
typedef struct ble_stream_t {
    dc_iostream_t base;       // The underlying iostream object
    ble_object_t *ble_object; // Our pointer to the BLE object
} ble_stream_t;

/*--------------------------------------------------------------------
 * Forward declarations for our custom vtable
 *------------------------------------------------------------------*/
static dc_status_t ble_stream_set_timeout   (dc_iostream_t *iostream, int timeout);
static dc_status_t ble_stream_read          (dc_iostream_t *iostream, void *data, size_t size, size_t *actual);
static dc_status_t ble_stream_write         (dc_iostream_t *iostream, const void *data, size_t size, size_t *actual);
static dc_status_t ble_stream_ioctl         (dc_iostream_t *iostream, unsigned int request, void *data_, size_t size_);
static dc_status_t ble_stream_sleep         (dc_iostream_t *iostream, unsigned int milliseconds);
static dc_status_t ble_stream_close         (dc_iostream_t *iostream);

/*--------------------------------------------------------------------
 * Build our custom vtable
 *------------------------------------------------------------------*/
static const dc_iostream_vtable_t ble_iostream_vtable = {
    .size          = sizeof(dc_iostream_vtable_t),
    .set_timeout   = ble_stream_set_timeout,
    .set_break     = NULL,
    .set_dtr       = NULL,
    .set_rts       = NULL,
    .get_lines     = NULL,
    .get_available = NULL,
    .configure     = NULL,
    .poll          = NULL,
    .read          = ble_stream_read,
    .write         = ble_stream_write,
    .ioctl         = ble_stream_ioctl,
    .flush         = NULL,
    .purge         = NULL,
    .sleep         = ble_stream_sleep,
    .close         = ble_stream_close,
};

/*--------------------------------------------------------------------
 * ble_iostream_create implementation
 *------------------------------------------------------------------*/
static dc_status_t ble_iostream_create(dc_iostream_t **out, dc_context_t *context, ble_object_t *bleobj)
{
    ble_stream_t *stream = (ble_stream_t *) malloc(sizeof(ble_stream_t));
    if (!stream) {
        if (context) {
            printf("ble_iostream_create: no memory");
        }
        return DC_STATUS_NOMEMORY;
    }
    memset(stream, 0, sizeof(*stream));

    stream->base.vtable = &ble_iostream_vtable;
    stream->base.context = context;
    stream->base.transport = DC_TRANSPORT_BLE;
    stream->ble_object = bleobj;

    *out = (dc_iostream_t *)stream;
    return DC_STATUS_SUCCESS;
}

/*--------------------------------------------------------------------
 * Vtable implementation functions
 *------------------------------------------------------------------*/
static dc_status_t ble_stream_set_timeout(dc_iostream_t *iostream, int timeout)
{
    ble_stream_t *s = (ble_stream_t *) iostream;
    return ble_set_timeout(s->ble_object, timeout);
}

static dc_status_t ble_stream_read(dc_iostream_t *iostream, void *data, size_t size, size_t *actual)
{
    ble_stream_t *s = (ble_stream_t *) iostream;
    return ble_read(s->ble_object, data, size, actual);
}

static dc_status_t ble_stream_write(dc_iostream_t *iostream, const void *data, size_t size, size_t *actual)
{
    ble_stream_t *s = (ble_stream_t *) iostream;
    return ble_write(s->ble_object, data, size, actual);
}

static dc_status_t ble_stream_ioctl(dc_iostream_t *iostream, unsigned int request, void *data_, size_t size_)
{
    ble_stream_t *s = (ble_stream_t *) iostream;
    return ble_ioctl(s->ble_object, request, data_, size_);
}

static dc_status_t ble_stream_sleep(dc_iostream_t *iostream, unsigned int milliseconds)
{
    ble_stream_t *s = (ble_stream_t *) iostream;
    return ble_sleep(s->ble_object, milliseconds);
}

static dc_status_t ble_stream_close(dc_iostream_t *iostream)
{
    ble_stream_t *s = (ble_stream_t *) iostream;
    dc_status_t rc = ble_close(s->ble_object);
    freeBLEObject(s->ble_object);
    free(s);
    return rc;
}

/*--------------------------------------------------------------------
 * Public functions
 *------------------------------------------------------------------*/
dc_status_t ble_packet_open(dc_iostream_t **iostream, dc_context_t *context, const char *devaddr, void *userdata) {
    // Initialize the Swift BLE manager singletons
    initializeBLEManager();

    // Create a BLE object
    ble_object_t *io = createBLEObject();
    if (io == NULL) {
        printf("ble_packet_open: Failed to create BLE object\n");
        return DC_STATUS_NOMEMORY;
    }

    // Connect to the device
    if (!connectToBLEDevice(io, devaddr)) {
        printf("ble_packet_open: Failed to connect to device\n");
        freeBLEObject(io);
        return DC_STATUS_IO;
    }

    // Create a custom BLE iostream
    dc_status_t status = ble_iostream_create(iostream, context, io);
    if (status != DC_STATUS_SUCCESS) {
        printf("ble_packet_open: Failed to create iostream\n");
        freeBLEObject(io);
        return status;
    }

    return DC_STATUS_SUCCESS;
}

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
    dc_iterator_t *iterator = NULL;
    dc_descriptor_t *descriptor = NULL;
    dc_status_t rc;

    rc = dc_descriptor_iterator(&iterator);
    if (rc != DC_STATUS_SUCCESS) {
        return rc;
    }

    while ((rc = dc_iterator_next(iterator, &descriptor)) == DC_STATUS_SUCCESS) {
        const char *product = dc_descriptor_get_product(descriptor);
        if (product && strstr(name, product) != NULL) {
            *family = (dc_family_t)dc_descriptor_get_type(descriptor);
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

dc_status_t open_ble_device(device_data_t *data, const char *devaddr, dc_family_t family, unsigned int model) {
    dc_status_t rc;
    dc_descriptor_t *descriptor = NULL;
    dc_iterator_t *iterator = NULL;

    // Create context if needed
    if (!data->context) {
        rc = dc_context_new(&data->context);
        if (rc != DC_STATUS_SUCCESS) {
            return rc;
        }
    }

    // Find descriptor matching family and model
    rc = dc_descriptor_iterator(&iterator);
    if (rc != DC_STATUS_SUCCESS) {
        return rc;
    }

    while ((rc = dc_iterator_next(iterator, &descriptor)) == DC_STATUS_SUCCESS) {
        if (dc_descriptor_get_type(descriptor) == family &&
            dc_descriptor_get_model(descriptor) == model) {
            break;
        }
        dc_descriptor_free(descriptor);
        descriptor = NULL;
    }

    dc_iterator_free(iterator);

    if (!descriptor) {
        return DC_STATUS_UNSUPPORTED;
    }

    // Use the existing function to open the device
    rc = open_ble_device_with_descriptor(data, devaddr, descriptor);
    dc_descriptor_free(descriptor);

    return rc;
}

dc_status_t create_parser(dc_parser_t **out,
                         dc_context_t *context,
                         dc_descriptor_t *descriptor,
                         const unsigned char data[],
                         size_t size) {
    return dc_parser_new2(out, context, descriptor, data, size);
} 
