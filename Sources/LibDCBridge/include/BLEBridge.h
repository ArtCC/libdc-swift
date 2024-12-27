#ifndef BLEBridge_h
#define BLEBridge_h

#include <stdio.h>
#include <stdbool.h>
#include "libdivecomputer/common.h"
#include "libdivecomputer/iostream.h"
#include "libdivecomputer/custom.h"
#include "libdivecomputer/parser.h"
#include "configuredc.h"

// Array helper functions
static inline uint16_t array_uint16_le(const unsigned char array[]) {
    return array[0] | (array[1] << 8);
}

static inline uint32_t array_uint32_le(const unsigned char array[]) {
    return array[0] | (array[1] << 8) | (array[2] << 16) | (array[3] << 24);
}

static inline uint16_t array_uint16_be(const unsigned char array[]) {
    return (array[0] << 8) | array[1];
}

static inline uint32_t array_uint32_be(const unsigned char array[]) {
    return (array[0] << 24) | (array[1] << 16) | (array[2] << 8) | array[3];
}

// BLE object
typedef struct ble_object {
    void* manager;
} ble_object_t;

// Device identification function
dc_status_t identify_ble_device(const char* name, dc_family_t* family, unsigned int* model);
dc_status_t open_ble_device(device_data_t *data, const char *devaddr, dc_family_t family, unsigned int model);

// Parser creation functions
dc_status_t suunto_eonsteel_parser_create(dc_parser_t **parser, dc_context_t *context, 
                                        const unsigned char *data, size_t size, 
                                        unsigned int devtime);
dc_status_t shearwater_petrel_parser_create(dc_parser_t **parser, dc_context_t *context, 
                                          const unsigned char *data, size_t size);
dc_status_t shearwater_predator_parser_create(dc_parser_t **parser, dc_context_t *context, 
                                            const unsigned char *data, size_t size);

// BLE object functions
ble_object_t* createBLEObject(void);
void freeBLEObject(ble_object_t* obj);

// BLE operations
dc_status_t ble_set_timeout(ble_object_t *io, int timeout);
dc_status_t ble_ioctl(ble_object_t *io, unsigned int request, void *data, size_t size);
dc_status_t ble_sleep(ble_object_t *io, unsigned int milliseconds);
dc_status_t ble_read(ble_object_t *io, void *data, size_t size, size_t *actual);
dc_status_t ble_write(ble_object_t *io, const void *data, size_t size, size_t *actual);
dc_status_t ble_close(ble_object_t *io);

// BLE setup functions
void initializeBLEManager(void);
bool connectToBLEDevice(ble_object_t *io, const char *deviceAddress);
bool discoverServices(ble_object_t *io);
bool enableNotifications(ble_object_t *io);

#ifdef __cplusplus
extern "C" {
#endif

dc_status_t identify_ble_device(const char* name, dc_family_t* family, unsigned int* model);
dc_status_t open_ble_device(device_data_t *data, const char *devaddr, dc_family_t family, unsigned int model);

#ifdef __cplusplus
}
#endif

#endif /* BLEBridge_h */
