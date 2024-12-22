#ifndef BLEBridge_h
#define BLEBridge_h

#include <stdio.h>
#include <stdbool.h>
#include "libdivecomputer/common.h"
#include "libdivecomputer/iostream.h"
#include "libdivecomputer/custom.h"
#include "configuredc.h"

typedef struct ble_object {
    void* manager;
} ble_object_t;

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

dc_status_t open_suunto_eonsteel(device_data_t *data, const char *devaddr);

#endif /* BLEBridge_h */
