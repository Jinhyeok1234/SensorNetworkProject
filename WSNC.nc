#include "WSN.h"
#include "message.h"

module WSNC {
  uses {
    interface Boot;
    interface Leds;
    
    interface SplitControl as RadioControl;
    interface SplitControl as SerialControl;

    interface Packet as CtpPacket;
    interface Packet as SerialPacket;

    // A2Trickle
    interface StdControl as DisseminationControl;
    interface DisseminationUpdate<cmd_msg_t> as CmdUpdate;
    interface DisseminationValue<cmd_msg_t> as CmdValue;
    interface CtpInfo;
    interface PacketAcknowledgements;

    // CTP
    interface StdControl as RoutingControl;
    interface RootControl;
    interface Send as CtpResSend;
    interface Receive as CtpResReceive;
    interface Send as CtpReportSend;
    interface Receive as CtpReportReceive;
    
    // Serial communication
    interface AMSend as SerialResSend;
    interface Receive as SerialCmdReceive;
    interface AMSend as SerialReportSend;

    // Sensors
    interface Read<uint16_t> as VoltageRead;
    interface Read<uint16_t> as TempRead;
    interface Read<uint16_t> as HumidityRead;
    interface Read<uint16_t> as LightRead;
    
    // Config (channel, tx power)
    interface CC2420Config;
    interface CC2420Packet;

    // Timer
    interface Timer<TMilli> as DataTimer;
    interface GlobalTime<TMilli>;
    interface LocalTime<TMilli>;
  }
}
implementation {
  message_t radio_pkt;
  message_t serial_pkt;
  
  bool radio_busy = FALSE;
  bool serial_busy = FALSE;
  
  uint16_t seq_counter = 0;
  uint8_t current_tx_power = 31;
  uint32_t report_interval = 10000; // initial: 10s
  uint8_t current_report_mask = REPORT_MASK_VOLTAGE | REPORT_MASK_TEMP; // initial: temperature and battery
  
  bool is_reporting = FALSE;
  uint8_t current_sample_step = 0;
  uint8_t report_value_count = 0;
  uint16_t report_values[7];

  void sample_next();

  // get local/global timestamp (!!!!global time is not working now!!!!)
  uint32_t get_timestamp(){
    uint32_t global_time;
    if (call GlobalTime.getGlobalTime(&global_time) == SUCCESS) {
      return global_time;
    }
    return call LocalTime.get();
  }

  // send response of command by CTP (Sensor Node -> Base Station)
  void send_response(uint8_t target, uint16_t val) {
    res_msg_t* res;
    if (radio_busy) return;
    
    //res = (res_msg_t*)call RadioPacket.getPayload(&radio_pkt, sizeof(res_msg_t));
    res = (res_msg_t*)call CtpPacket.getPayload(&radio_pkt, sizeof(res_msg_t));
    if (res == NULL) return;
    
    res->node_id = TOS_NODE_ID;
    res->seq_num = seq_counter++;
    res->timestamp = get_timestamp();
    res->target_command = target;
    res->value = val;
    
    call CC2420Packet.setPower(&radio_pkt, current_tx_power);

    call PacketAcknowledgements.requestAck(&radio_pkt);

    //if (call RadioResSend.send(BASE_STATION_ID, &radio_pkt, sizeof(res_msg_t)) == SUCCESS) {
    if (call CtpResSend.send(&radio_pkt, sizeof(res_msg_t)) == SUCCESS) {
      radio_busy = TRUE;
    }
  }

  // send report by CTP (Sensor Node -> Base Station)
  void send_report() {
    report_msg_t* rep;
    uint8_t i;
    uint16_t current_etx;
    if (radio_busy) {
      is_reporting = FALSE;
      return;
    }
    
    rep = (report_msg_t*)call CtpPacket.getPayload(&radio_pkt, sizeof(report_msg_t));
    if (rep == NULL) {
      is_reporting = FALSE;
      return;
    }
    
    rep->node_id = TOS_NODE_ID;
    rep->seq_num = seq_counter++;
    rep->timestamp = get_timestamp();
    if (TOS_NODE_ID == BASE_STATION_ID) {
      rep->parent_id = BASE_STATION_ID;
      rep->etx = 0;
    } else {
      am_addr_t parent;
      if (call CtpInfo.getParent(&parent) == SUCCESS) {
        rep->parent_id = parent;
      } else {
        rep->parent_id = 0xFFFF; // no/unknown parent
      }

      if (call CtpInfo.getEtx(&current_etx) == SUCCESS) {
        rep->etx = current_etx;
      } else {
        rep->etx = 0xFFFF; // exception value for collection fault
      }
    }
    rep->report_setting = current_report_mask;
    for (i = 0; i < report_value_count; i++) {
      rep->values[i] = report_values[i];
    }
    
    call CC2420Packet.setPower(&radio_pkt, current_tx_power);

    call PacketAcknowledgements.requestAck(&radio_pkt);
    
    if (call CtpReportSend.send(&radio_pkt, sizeof(report_msg_t)) == SUCCESS) {
      radio_busy = TRUE;
    } else {
      is_reporting = FALSE;
    }
  }

  // record sensor sequentially for report
  void record_and_next(uint16_t val) {
    if (report_value_count < 7) {
      report_values[report_value_count++] = val;
    }
    current_sample_step++;
    sample_next();
  }

  // read sensor sequentially for report
  void sample_next() {
    while (current_sample_step < 7) {
      if (current_report_mask & (1 << current_sample_step)) {
        if (current_sample_step == 0) { record_and_next(call Leds.get()); return; }
        else if (current_sample_step == 1) { call VoltageRead.read(); return; }
        else if (current_sample_step == 2) { call TempRead.read(); return; }
        else if (current_sample_step == 3) { record_and_next(call CC2420Config.getChannel()); return; }
        else if (current_sample_step == 4) { record_and_next(current_tx_power); return; }
        else if (current_sample_step == 5) { call LightRead.read(); return; }
        else if (current_sample_step == 6) { call HumidityRead.read(); return; }
      }
      current_sample_step++;
    }
    send_report();
  }

  event void Boot.booted() {
    call RadioControl.start();
    call SerialControl.start();
    call RoutingControl.start();
    call DisseminationControl.start();
    
    if (TOS_NODE_ID == BASE_STATION_ID) {
      call RootControl.setRoot();
    } else {
      call DataTimer.startPeriodic(report_interval);
    }
  }

  // event for periodic report
  event void DataTimer.fired() {
    if (TOS_NODE_ID != BASE_STATION_ID && !is_reporting && current_report_mask != 0) {
      is_reporting = TRUE;
      current_sample_step = 0;
      report_value_count = 0;
      sample_next();
    }
  }

  event void RadioControl.startDone(error_t err) {}
  event void RadioControl.stopDone(error_t err) {}
  event void SerialControl.startDone(error_t err) {}
  event void SerialControl.stopDone(error_t err) {}

  // receive command by serial port (PC -> Base Station)
  event message_t* SerialCmdReceive.receive(message_t* msg, void* payload, uint8_t len) {
    if (TOS_NODE_ID == BASE_STATION_ID) {
      cmd_msg_t* src = (cmd_msg_t*)payload;
      call CmdUpdate.change(src);
    }
    return msg;
  }

  // receive command by A2Trickle (Base Station -> Sensor Node)
  event void CmdValue.changed() {
    if (TOS_NODE_ID != BASE_STATION_ID) {
      const cmd_msg_t* cmd = call CmdValue.get();
      
      if (cmd->dest_node != TOS_NODE_ID && cmd->dest_node != 0xFFFF) return;
      
      if (cmd->command_type == CMD_GET) {
        if (cmd->target_command == TARGET_LED) send_response(TARGET_LED, call Leds.get());
        else if (cmd->target_command == TARGET_VOLTAGE) call VoltageRead.read();
        else if (cmd->target_command == TARGET_TEMP) call TempRead.read();
        else if (cmd->target_command == TARGET_HUMIDITY) call HumidityRead.read();
        else if (cmd->target_command == TARGET_LIGHT) call LightRead.read();
        else if (cmd->target_command == TARGET_CHANNEL) send_response(TARGET_CHANNEL, call CC2420Config.getChannel());
        else if (cmd->target_command == TARGET_TX_POWER) send_response(TARGET_TX_POWER, current_tx_power);
        else if (cmd->target_command == TARGET_REPORT_INTERVAL) send_response(TARGET_REPORT_INTERVAL, report_interval);
        else if (cmd->target_command == TARGET_REPORT) send_response(TARGET_REPORT, current_report_mask);
      } 
      else if (cmd->command_type == CMD_SET) {
        if (cmd->target_command == TARGET_LED) {
          call Leds.set(cmd->value);
          send_response(TARGET_LED, call Leds.get());
        //} else if (cmd->target_command == TARGET_CHANNEL) {
        //  call CC2420Config.setChannel(cmd->value);
        //  call CC2420Config.sync();
        } else if (cmd->target_command == TARGET_TX_POWER) {
          current_tx_power = cmd->value;
          send_response(TARGET_TX_POWER, current_tx_power);
        } else if (cmd->target_command == TARGET_REPORT_INTERVAL) {
          report_interval = cmd->value;
          if (report_interval < 100) report_interval = 100;
          call DataTimer.stop();
          call DataTimer.startPeriodic(report_interval);
          send_response(TARGET_REPORT_INTERVAL, report_interval);
        } else if (cmd->target_command == TARGET_REPORT) {
          current_report_mask = cmd->value & 0x7F;
          send_response(TARGET_REPORT, current_report_mask);
        }
      }
    }
  }

  // receive response by CTP (Sensor Node -> Base Station)
  event message_t* CtpResReceive.receive(message_t* msg, void* payload, uint8_t len) {
    if (TOS_NODE_ID == BASE_STATION_ID) {
      res_msg_t* src = (res_msg_t*)payload;
      res_msg_t* dest = (res_msg_t*)call SerialPacket.getPayload(&serial_pkt, sizeof(res_msg_t));
      if (dest == NULL) return msg;
      memcpy(dest, src, sizeof(res_msg_t));
      if (!serial_busy) {
        if (call SerialResSend.send(AM_BROADCAST_ADDR, &serial_pkt, sizeof(res_msg_t)) == SUCCESS) {
          serial_busy = TRUE;
        }
      }
    }
    return msg;
  }

  // receive periodic report by CTP (Sensor Node -> Base Station)
  event message_t* CtpReportReceive.receive(message_t* msg, void* payload, uint8_t len) {
    if (TOS_NODE_ID == BASE_STATION_ID) {
      report_msg_t* src = (report_msg_t*)payload;
      report_msg_t* dest = (report_msg_t*)call SerialPacket.getPayload(&serial_pkt, sizeof(report_msg_t));
      if (dest == NULL) return msg;
      memcpy(dest, src, sizeof(report_msg_t));
      if (!serial_busy) {
        if (call SerialReportSend.send(AM_BROADCAST_ADDR, &serial_pkt, sizeof(report_msg_t)) == SUCCESS) {
          serial_busy = TRUE;
        }
      }
    }
    return msg;
  }

  event void CtpResSend.sendDone(message_t* msg, error_t err) { radio_busy = FALSE; }
  event void CtpReportSend.sendDone(message_t* msg, error_t err) {
    radio_busy = FALSE;
    is_reporting = FALSE; 
  }

  event void SerialResSend.sendDone(message_t* msg, error_t err) { serial_busy = FALSE; }
  event void SerialReportSend.sendDone(message_t* msg, error_t err) { serial_busy = FALSE; }

  event void VoltageRead.readDone(error_t result, uint16_t val) {
    if (is_reporting) record_and_next(val);
    else if (result == SUCCESS) send_response(TARGET_VOLTAGE, val);
  }
  event void TempRead.readDone(error_t result, uint16_t val) {
    if (is_reporting) record_and_next(val);
    else if (result == SUCCESS) send_response(TARGET_TEMP, val);
  }
  event void HumidityRead.readDone(error_t result, uint16_t val) {
    if (is_reporting) record_and_next(val);
    else if (result == SUCCESS) send_response(TARGET_HUMIDITY, val);
  }
  event void LightRead.readDone(error_t result, uint16_t val) {
    if (is_reporting) record_and_next(val);
    else if (result == SUCCESS) send_response(TARGET_LIGHT, val);
  }
  
  event void CC2420Config.syncDone(error_t error) {
    if (error == SUCCESS && !is_reporting) send_response(TARGET_CHANNEL, call CC2420Config.getChannel());
  }
}