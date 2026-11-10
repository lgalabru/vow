#ifndef VOW_H
#define VOW_H
#include <stdint.h>
#include <stddef.h>
// Version 1. Inputs are borrowed for the call; outputs are freed with vow_string_free_v1.
uint64_t vow_session_create_v1(void);
void vow_session_destroy_v1(uint64_t session);
char *vow_dispatch_v1(uint64_t session, const uint8_t *data, size_t len);
char *vow_profile_transaction_v1(const uint8_t *data, size_t len);
void vow_string_free_v1(char *value);
#endif
