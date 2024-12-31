#ifndef libdcswift_bridging_header_h
#define libdcswift_bridging_header_h

// Include local headers
#include "BLEBridge.h"
#include "configuredc.h"

// Include libdivecomputer headers
#include <libdivecomputer/device.h>
#include <libdivecomputer/common.h>
#include <libdivecomputer/parser.h>
#include <libdivecomputer/context.h>
#include <libdivecomputer/descriptor.h>
#include <libdivecomputer/iterator.h>

// Callback types for Swift
typedef void (*dc_sample_callback_t)(dc_sample_type_t type, 
                                   const dc_sample_value_t *value, 
                                   void *userdata);

typedef int (*dc_dive_callback_t)(const unsigned char *data, 
                                unsigned int size, 
                                const unsigned char *fingerprint, 
                                unsigned int fsize,
                                void *userdata);

// Descriptor functions
dc_family_t dc_descriptor_get_type(dc_descriptor_t *descriptor);
unsigned int dc_descriptor_get_model(dc_descriptor_t *descriptor);
dc_status_t create_parser_for_device(dc_parser_t **parser, dc_context_t *context, dc_family_t family, unsigned int model, const unsigned char *data, size_t size);
dc_status_t find_matching_descriptor(dc_descriptor_t **out_descriptor, 
    dc_family_t family, unsigned int model, const char *name);

// Export Objective-C classes to Swift
#if __has_feature(objc_modules)
@import Foundation;
@import CoreBluetooth;
#else
#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#endif

#endif /* libdcswift_bridging_header_h */
