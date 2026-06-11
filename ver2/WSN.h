#ifndef WSN_H
#define WSN_H

enum {
  AM_CMD_MSG = 0x10,
  AM_RES_MSG = 0x11,
  AM_REPORT_MSG = 0x20,
  COL_CTP_RES = 0x31,
  COL_CTP_REPORT = 0x32,
  DISSEMINATION_KEY_CMD = 0x1234,
  BASE_STATION_ID = 0
};

enum {
  CMD_GET = 0x01,
  CMD_SET = 0x02
};

enum {
  TARGET_LED = 0x01,
  TARGET_VOLTAGE = 0x02,
  TARGET_TEMP = 0x03,
  TARGET_CHANNEL = 0x04,
  TARGET_TX_POWER = 0x05,
  TARGET_LIGHT = 0x06,
  TARGET_HUMIDITY = 0x07,
  TARGET_REPORT = 0x08,
  TARGET_REPORT_INTERVAL = 0x09
};

enum {
  REPORT_MASK_LED       = 0x01,  /* 0000001 */
  REPORT_MASK_VOLTAGE   = 0x02,  /* 0000010 */
  REPORT_MASK_TEMP      = 0x04,  /* 0000100 */
  REPORT_MASK_CHANNEL   = 0x08,  /* 0001000 */
  REPORT_MASK_TX_POWER  = 0x10,  /* 0010000 */
  REPORT_MASK_LIGHT     = 0x20,  /* 0100000 */
  REPORT_MASK_HUMIDITY  = 0x40   /* 1000000 */
};

typedef nx_struct cmd_msg {
  nx_uint8_t command_type;
  nx_uint8_t target_command;
  nx_uint16_t value;
  nx_uint16_t dest_node; /* node ID (0xFFFF = Broadcast) */
} cmd_msg_t;

typedef nx_struct res_msg {
  nx_uint16_t node_id;
  nx_uint16_t seq_num;
  nx_uint32_t timestamp;
  nx_uint8_t target_command;
  nx_uint16_t value;
} res_msg_t;

typedef nx_struct report_msg {
  nx_uint16_t node_id;
  nx_uint16_t seq_num;
  nx_uint32_t timestamp;
  nx_uint16_t parent_id;
  nx_uint8_t report_setting;
  nx_uint16_t values[7];
} report_msg_t;

#endif
