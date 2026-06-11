#ifndef A2_TRICKLE_H
#define A2_TRICKLE_H

#include "WSN.h"

typedef nx_struct a2_trickle_msg {
  nx_uint16_t seq_num;
  nx_uint16_t sender_id;
  cmd_msg_t cmd;
} a2_trickle_msg_t;

#endif