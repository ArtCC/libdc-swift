#include "configuredc.h"
#include "BLEBridge.h"
#include <libdivecomputer/device.h>
#include <libdivecomputer/descriptor.h>
#include <libdivecomputer/iostream.h>
#include <libdivecomputer/parser.h>
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
 * Build custom vtable
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
 * Creates a BLE iostream instance
 * 
 * @param out:     Output parameter for created iostream
 * @param context: Dive computer context
 * @param bleobj:  BLE object to associate with the stream
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
 * @note: Takes ownership of the bleobj
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
 * Sets the timeout for BLE operations
 * 
 * @param iostream: The iostream instance
 * @param timeout:  Timeout value in milliseconds
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
 *------------------------------------------------------------------*/
static dc_status_t ble_stream_set_timeout(dc_iostream_t *iostream, int timeout)
{
    ble_stream_t *s = (ble_stream_t *) iostream;
    return ble_set_timeout(s->ble_object, timeout);
}

/*--------------------------------------------------------------------
 * Reads data from the BLE device
 * 
 * @param iostream: The iostream instance
 * @param data:     Buffer to store read data
 * @param size:     Size of the buffer
 * @param actual:   Output parameter for bytes actually read
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
 *------------------------------------------------------------------*/
static dc_status_t ble_stream_read(dc_iostream_t *iostream, void *data, size_t size, size_t *actual)
{
    ble_stream_t *s = (ble_stream_t *) iostream;
    return ble_read(s->ble_object, data, size, actual);
}

/*--------------------------------------------------------------------
 * Writes data to the BLE device
 * 
 * @param iostream: The iostream instance
 * @param data:     Data to write
 * @param size:     Size of the data
 * @param actual:   Output parameter for bytes actually written
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
 *------------------------------------------------------------------*/
static dc_status_t ble_stream_write(dc_iostream_t *iostream, const void *data, size_t size, size_t *actual)
{
    ble_stream_t *s = (ble_stream_t *) iostream;
    return ble_write(s->ble_object, data, size, actual);
}

/*--------------------------------------------------------------------
 * Performs device-specific control operations
 * 
 * @param iostream: The iostream instance
 * @param request:  Control request code
 * @param data_:    Request-specific data
 * @param size_:    Size of the data
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
 *------------------------------------------------------------------*/
static dc_status_t ble_stream_ioctl(dc_iostream_t *iostream, unsigned int request, void *data_, size_t size_)
{
    ble_stream_t *s = (ble_stream_t *) iostream;
    return ble_ioctl(s->ble_object, request, data_, size_);
}

/*--------------------------------------------------------------------
 * Suspends execution for specified duration
 * 
 * @param iostream:     The iostream instance
 * @param milliseconds: Duration to sleep in milliseconds
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
 *------------------------------------------------------------------*/
static dc_status_t ble_stream_sleep(dc_iostream_t *iostream, unsigned int milliseconds)
{
    ble_stream_t *s = (ble_stream_t *) iostream;
    return ble_sleep(s->ble_object, milliseconds);
}

/*--------------------------------------------------------------------
 * Closes the BLE stream and frees resources
 * 
 * @param iostream: The iostream instance to close
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
 *------------------------------------------------------------------*/
static dc_status_t ble_stream_close(dc_iostream_t *iostream)
{
    ble_stream_t *s = (ble_stream_t *) iostream;
    dc_status_t rc = ble_close(s->ble_object);
    freeBLEObject(s->ble_object);
    free(s);
    return rc;
}

/*--------------------------------------------------------------------
 * Opens a BLE packet connection to a dive computer
 * 
 * @param iostream: Output parameter for created iostream
 * @param context:  Dive computer context
 * @param devaddr:  BLE device address/UUID
 * @param userdata: User-provided context data
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
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

/*--------------------------------------------------------------------
 * Event callback function for device events
 * 
 * @param device:   The dive computer device
 * @param event:    Type of event received
 * @param data:     Event-specific data
 * @param userdata: User-provided context (device_data_t pointer)
 *------------------------------------------------------------------*/
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

/*--------------------------------------------------------------------
 * Closes and frees resources associated with a device_data structure
 * 
 * @param data: Pointer to device_data_t structure to clean up
 * @note: Does not free the descriptor as it's managed by the caller
 *------------------------------------------------------------------*/
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
    // The descriptor is freed by the caller
    data->descriptor = NULL;
}

/*--------------------------------------------------------------------
 * Opens a BLE device using a provided descriptor
 * 
 * @param data:       Pointer to device_data_t to store device info
 * @param devaddr:    BLE device address/UUID
 * @param descriptor: Device descriptor for the dive computer
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
 * @note: Takes ownership of the device_data_t structure
 *------------------------------------------------------------------*/
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

    // Store the descriptor (without reference counting)
    data->descriptor = descriptor;

    return rc;
}

/*--------------------------------------------------------------------
 * Helper function to find a matching device descriptor
 * 
 * @param out_descriptor: Output parameter for found descriptor
 * @param family:         Device family to match (ignored if name provided)
 * @param model:          Device model to match (ignored if name provided)
 * @param name:           Device name to match (takes precedence over family/model)
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
 * @note: Caller must free the returned descriptor when done
 *------------------------------------------------------------------*/
dc_status_t find_matching_descriptor(dc_descriptor_t **out_descriptor, 
    dc_family_t family, unsigned int model, const char *name) {
    
    dc_iterator_t *iterator = NULL;
    dc_descriptor_t *descriptor = NULL;
    dc_status_t rc;

    rc = dc_descriptor_iterator(&iterator);
    if (rc != DC_STATUS_SUCCESS) {
        return rc;
    }

    while ((rc = dc_iterator_next(iterator, &descriptor)) == DC_STATUS_SUCCESS) {
        bool matches = false;
        
        if (name != NULL) {
            // Match by name
            const char *product = dc_descriptor_get_product(descriptor);
            if (product && strstr(name, product) != NULL) {
                matches = true;
            }
        } else {
            // Match by family and model
            if (dc_descriptor_get_type(descriptor) == family &&
                dc_descriptor_get_model(descriptor) == model) {
                matches = true;
            }
        }
        
        if (matches) {
            *out_descriptor = descriptor;
            dc_iterator_free(iterator);
            return DC_STATUS_SUCCESS;
        }
        dc_descriptor_free(descriptor);
    }

    dc_iterator_free(iterator);
    return DC_STATUS_UNSUPPORTED;
}

/*--------------------------------------------------------------------
 * Identifies a BLE device's family and model from its name
 * 
 * @param name:   Device name to identify
 * @param family: Output parameter for identified device family
 * @param model:  Output parameter for identified device model
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
 *------------------------------------------------------------------*/
dc_status_t identify_ble_device(const char* name, dc_family_t* family, unsigned int* model) {
    dc_descriptor_t *descriptor = NULL;
    dc_status_t rc;

    rc = find_matching_descriptor(&descriptor, DC_FAMILY_NULL, 0, name);
    if (rc != DC_STATUS_SUCCESS) {
        return rc;
    }

    *family = (dc_family_t)dc_descriptor_get_type(descriptor);
    *model = dc_descriptor_get_model(descriptor);
    dc_descriptor_free(descriptor);
    return DC_STATUS_SUCCESS;
}

/*--------------------------------------------------------------------
 * Opens a BLE device connection using family and model information
 * 
 * @param data:    Pointer to device_data_t to store device info
 * @param devaddr: BLE device address/UUID
 * @param family:  Device family identifier
 * @param model:   Device model identifier
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
 *------------------------------------------------------------------*/
dc_status_t open_ble_device(device_data_t *data, const char *devaddr, dc_family_t family, unsigned int model) {
    dc_status_t rc;
    dc_descriptor_t *descriptor = NULL;

    if (!data->context) {
        rc = dc_context_new(&data->context);
        if (rc != DC_STATUS_SUCCESS) {
            return rc;
        }
    }

    rc = find_matching_descriptor(&descriptor, family, model, NULL);
    if (rc != DC_STATUS_SUCCESS) {
        return rc;
    }

    rc = open_ble_device_with_descriptor(data, devaddr, descriptor);
    dc_descriptor_free(descriptor);

    return rc;
}

/*--------------------------------------------------------------------
 * Creates a dive data parser for a specific device model
 * 
 * @param parser:  Output parameter for created parser
 * @param context: Dive computer context
 * @param family:  Device family identifier
 * @param model:   Device model identifier
 * @param data:    Raw dive data to parse
 * @param size:    Size of raw dive data
 * 
 * @return: DC_STATUS_SUCCESS on success, error code otherwise
 * @note: Caller must free the returned parser when done
 *------------------------------------------------------------------*/
dc_status_t create_parser_for_device(dc_parser_t **parser, dc_context_t *context, 
    dc_family_t family, unsigned int model, const unsigned char *data, size_t size) 
{
    dc_status_t rc;
    dc_descriptor_t *descriptor = NULL;

    rc = find_matching_descriptor(&descriptor, family, model, NULL);
    if (rc != DC_STATUS_SUCCESS) {
        return rc;
    }

    // Create parser
    rc = dc_parser_new2(parser, context, descriptor, data, size);
    dc_descriptor_free(descriptor);

    return rc;
}