#include "configuredc.h"
#include <libdivecomputer/common.h>
#include <libdivecomputer/context.h>
#include <libdivecomputer/iostream.h>
#include "iostream-private.h"
#include <libdivecomputer/custom.h>
#include <hdlc.h>
#include "suunto_eonsteel.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "BLEBridge.h"

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
 * We can set all unneeded methods to NULL if we don't support them.
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
 * ble_iostream_create: Equivalent to a "dc_custom_open"-style function.
 *------------------------------------------------------------------*/
static dc_status_t ble_iostream_create(dc_iostream_t **out, dc_context_t *context, ble_object_t *bleobj)
{
    // 1) Allocate a new ble_stream_t
    ble_stream_t *stream = (ble_stream_t *) malloc(sizeof(ble_stream_t));
    if (!stream) {
        if (context) {
            printf("ble_iostream_create: no memory");
        }
        return DC_STATUS_NOMEMORY;
    }
    memset(stream, 0, sizeof(*stream));

    // 2) Initialize the base iostream
    //    We'll use the vtable ble_iostream_vtable, no custom transport yet
    stream->base.vtable = &ble_iostream_vtable;
    stream->base.context = context;
    stream->base.transport = DC_TRANSPORT_BLE;  // Mark it as BLE
    // 3) Store our ble_object in the extension struct
    stream->ble_object = bleobj;

    // 4) Return final iostream pointer
    *out = (dc_iostream_t *)stream;
    return DC_STATUS_SUCCESS;
}

/*--------------------------------------------------------------------
 * Wrappers for iostream vtable
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
    
    // 1) Close the peripheral (calls manager->close).
    dc_status_t rc = ble_close(s->ble_object);
    
    // 2) Now free that ble_object_t pointer itself.
    freeBLEObject(s->ble_object);

    // 3) Then free the ble_stream_t structure.
    free(s);

    return rc;
}

/*--------------------------------------------------------------------
 * ble_packet_open: The main function to connect via BLE, discover, etc.
 * Then we create our custom BLE iostream with ble_iostream_create.
 *------------------------------------------------------------------*/
dc_status_t ble_packet_open(dc_iostream_t **iostream, dc_context_t *context, const char *devaddr, void *userdata) {
    printf("ble_packet_open: Starting for device %s\n", devaddr);
    
    // 1) Initialize the Swift BLE manager singletons
    initializeBLEManager();

    // 2) Create a BLE object
    ble_object_t *io = createBLEObject();
    if (io == NULL) {
        printf("ble_packet_open: Failed to create BLE object\n");
        return DC_STATUS_NOMEMORY;
    }

    // 3) Connect to the device
    if (!connectToBLEDevice(io, devaddr)) {
        printf("ble_packet_open: Failed to connect to device\n");
        freeBLEObject(io);  // Free immediately on connection failure
        return DC_STATUS_IO;
    }
    printf("ble_packet_open: Connected to device\n");

    // 4) Create a custom BLE iostream
    dc_status_t status = ble_iostream_create(iostream, context, io);
    if (status != DC_STATUS_SUCCESS) {
        printf("ble_packet_open: Failed to create iostream\n");
        freeBLEObject(io);  // Free immediately on iostream creation failure
        return status;
    }
    printf("ble_packet_open: Successfully created iostream\n");

    // 5) Return success (the ble_object is now "owned" by iostream)
    return DC_STATUS_SUCCESS;
}

/*--------------------------------------------------------------------
 * open_suunto_eonsteel: Create context, call ble_packet_open,
 * then suunto_eonsteel_device_open (which will do HDLC internally).
 *------------------------------------------------------------------*/
static void close_device_data(device_data_t *data) {
    if (!data)
        return;
        
    if (data->device) {
        dc_device_close(data->device);
        data->device = NULL;
    }
    if (data->iostream) {
        dc_iostream_close(data->iostream);  // This will trigger ble_stream_close
        data->iostream = NULL;
    }
    if (data->context) {
        dc_context_free(data->context);
        data->context = NULL;
    }
}

dc_status_t open_suunto_eonsteel(device_data_t *data, const char *devaddr) {
    dc_status_t rc;
    printf("Starting open_suunto_eonsteel with address: %s\n", devaddr);
    
    if (!data) {
        printf("Invalid device_data pointer\n");
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
    printf("Context created successfully\n");

    // Create BLE iostream
    rc = ble_packet_open(&data->iostream, data->context, devaddr, data);
    if (rc != DC_STATUS_SUCCESS) {
        printf("Failed to open BLE connection, rc=%d\n", rc);
        close_device_data(data);
        return rc;
    }
    printf("BLE iostream created successfully\n");

    // Wait a bit for the connection to stabilize
    dc_iostream_sleep(data->iostream, 1000);

    // Open Suunto device
    rc = suunto_eonsteel_device_open(&data->device, data->context, data->iostream, 2);
    if (rc != DC_STATUS_SUCCESS) {
        printf("Failed to open Suunto device, rc=%d\n", rc);
        return rc;
    }
    printf("Suunto device opened successfully\n");

    return DC_STATUS_SUCCESS;
}
