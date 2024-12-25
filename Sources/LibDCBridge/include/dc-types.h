#ifndef DC_TYPES_H
#define DC_TYPES_H

#ifdef __cplusplus
extern "C" {
#endif

#include <libdivecomputer/common.h>
#include <libdivecomputer/context.h>
#include <libdivecomputer/descriptor.h>
#include <libdivecomputer/device.h>
#include <libdivecomputer/parser.h>
#include <libdivecomputer/iterator.h>

// Re-declare the types to ensure they're visible
typedef struct dc_context_t dc_context_t;
typedef struct dc_parser_t dc_parser_t;
typedef struct dc_descriptor_t dc_descriptor_t;
typedef struct dc_iterator_t dc_iterator_t;

#ifdef __cplusplus
}
#endif

#endif /* DC_TYPES_H */ 