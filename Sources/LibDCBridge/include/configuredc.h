#ifndef CONFIGUREDC_H
#define CONFIGUREDC_H

#include <stdbool.h>
#include <stdint.h>
#include <libdivecomputer/common.h>
#include <libdivecomputer/iostream.h>
#include <libdivecomputer/context.h>
#include <libdivecomputer/descriptor.h>
#include <libdivecomputer/device.h>
#include <libdivecomputer/parser.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    dc_device_t *device;
    dc_context_t *context;
    dc_iostream_t *iostream;
    dc_descriptor_t *descriptor;
    
    // device info
    int have_devinfo;
    dc_event_devinfo_t devinfo;
    int have_progress;
    dc_event_progress_t progress;
    int have_clock;
    dc_event_clock_t clock;
    
    // fingerprints
    unsigned char *fingerprint;  
    unsigned int fsize;         
    void *fingerprint_context;  // Context to pass to lookup function
    unsigned char *(*lookup_fingerprint)(void *context, const char *device_type, const char *serial, size_t *size);
    
    // device identification
    const char *model;     // Model string (from descriptor)
    uint32_t fdeviceid;   // Device ID associated with fingerprint
    uint32_t fdiveid;     // Dive ID associated with fingerprint
} device_data_t;

dc_status_t ble_packet_open(dc_iostream_t **iostream, dc_context_t *context, const char *devaddr, void *userdata);
dc_status_t open_ble_device(device_data_t *data, const char *devaddr, dc_family_t family, unsigned int model);
dc_status_t identify_ble_device(const char* name, dc_family_t* family, unsigned int* model);
dc_status_t open_ble_device_with_descriptor(device_data_t *data, const char *devaddr, dc_descriptor_t *descriptor);
dc_status_t create_parser_for_device(dc_parser_t **parser, dc_context_t *context, dc_family_t family, unsigned int model, const unsigned char *data, size_t size);
device_data_t* get_device_data_pointer(void);
dc_status_t find_matching_descriptor(dc_descriptor_t **out_descriptor, 
    dc_family_t family, unsigned int model, const char *name);

#ifdef __cplusplus
}
#endif

#endif /* CONFIGUREDC_H */ 