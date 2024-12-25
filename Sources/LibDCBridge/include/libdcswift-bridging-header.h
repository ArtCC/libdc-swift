#ifndef libdcswift_bridging_header_h
#define libdcswift_bridging_header_h

#include "dc-types.h"
#include "BLEBridge.h"
#include "configuredc.h"

// Define callback types for Swift
typedef void (*dc_sample_callback_t)(dc_sample_type_t type, 
                                   const dc_sample_value_t *value, 
                                   void *userdata);

typedef int (*dc_dive_callback_t)(const unsigned char *data, 
                                unsigned int size, 
                                const unsigned char *fingerprint, 
                                unsigned int fsize,
                                void *userdata);

#endif /* libdcswift_bridging_header_h */
