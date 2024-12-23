#ifndef CONFIGUREDC_H
#define CONFIGUREDC_H

#include <stdbool.h>
#include <libdivecomputer/common.h>
#include <libdivecomputer/iostream.h>
#include <libdivecomputer/context.h>

typedef struct {
    dc_device_t *device;
    dc_context_t *context;
    dc_iostream_t *iostream;
    
    int have_devinfo;
    dc_event_devinfo_t devinfo;
    
    int have_progress;
    dc_event_progress_t progress;
    
    int have_clock;
    dc_event_clock_t clock;
} device_data_t;

dc_status_t open_ble_device(device_data_t *data, const char *devaddr, dc_family_t family, unsigned int model);
dc_status_t identify_ble_device(const char* name, dc_family_t* family, unsigned int* model);
dc_status_t open_ble_device_with_descriptor(device_data_t *data, const char *devaddr, dc_descriptor_t *descriptor);

#endif /* CONFIGUREDC_H */ 