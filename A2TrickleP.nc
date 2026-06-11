#include "A2Trickle.h"

module A2TrickleP {
  provides {
    interface StdControl;
    interface DisseminationUpdate<cmd_msg_t>;
    interface DisseminationValue<cmd_msg_t>;
  }
  uses {
    interface AMSend as TrickleSend;
    interface Receive as TrickleReceive;

    // !!!!does not work!!!!
    interface Timer<TMilli> as AlignedTimer;
    interface GlobalTime<TMilli>;

    interface Random;
    interface CtpInfo;
    interface Intercept;
    interface LocalTime<TMilli>;// fallback for global time
  }
}
implementation {
  bool is_running = FALSE;
  bool radio_busy = FALSE;
  message_t pkt;
  
  uint32_t current_I = 64000UL; // initial : 64s
  uint16_t current_seq = 0;
  uint16_t c_counter = 0; // suppression counter
  cmd_msg_t current_cmd;

  uint8_t current_level = 0;       // hop count
  uint8_t dependent_neighbors = 0; // number of dependent neighbors (now, use CTP childrens naively)

  uint32_t a2_i_min = 1000UL; 
  uint32_t a2_i_max = 64000UL;
  uint16_t a2_k_threshold = 2;

  enum {
    STATE_WAIT_TX = 1,
    STATE_WAIT_BOUNDARY = 2
  };
  uint8_t timer_state = STATE_WAIT_BOUNDARY;
  
  // get local/global timestamp (!!!!global time is not working now!!!!)
  uint32_t get_global_time() {
    uint32_t gt;
    if (call GlobalTime.getGlobalTime(&gt) == SUCCESS) {
      return gt;
    }
    // return 0;
    return call LocalTime.get();
  }

  // intercept CTP forwarding to check dependent neighbors
  event bool Intercept.forward(message_t* msg, void* payload, uint8_t len) {
    dependent_neighbors = 1; 
    return TRUE;
  }

  // apply trickle config from command
  void apply_trickle_config() {
    if (current_cmd.target_command == TARGET_TRICKLE_I_MIN) {
      a2_i_min = current_cmd.value;
    } else if (current_cmd.target_command == TARGET_TRICKLE_I_MAX) {
      a2_i_max = current_cmd.value;
    } else if (current_cmd.target_command == TARGET_TRICKLE_K) {
      a2_k_threshold = current_cmd.value;
    }
  }

  // align timer to interval boundary
  void reset_aligned_timer() {
    uint32_t gt = get_global_time();
    uint32_t delay;
    uint32_t I_half = current_I / 2;
    uint32_t gt_start;
    uint32_t gt_end;
    uint32_t offset;
    uint32_t gt_tx;
    uint16_t current_etx;
    uint32_t slot_size;
    uint32_t num_slots;
    uint32_t allowed_slots;
    uint32_t random_slot_choice;
    uint32_t target_slot_index;
    
    //if (gt == 0) {
    //  if (timer_state == STATE_WAIT_BOUNDARY) {
    //    timer_state = STATE_WAIT_TX;
    //    call AlignedTimer.startOneShot(current_I / 2);
    //  } else {
    //    timer_state = STATE_WAIT_BOUNDARY;
    //    call AlignedTimer.startOneShot(current_I / 2);
    //  }
    //}
    
    // current interval bounds
    gt_start = gt - (gt % current_I);
    gt_end = gt_start + current_I;

    // calculate current level from CTP ETX
    if (call CtpInfo.getEtx(&current_etx) == SUCCESS) {
      // suppose 10 ETX = 1 level
      // it's not intended structure; should be changed
      current_level = current_etx / 10;
    } else {
      current_level = 0; // root or disconnected
    }
    
    // Tiling: divide [I/2, I] into I_min/4 slots
    slot_size = a2_i_min / 4;
    num_slots = I_half / slot_size;
    allowed_slots = num_slots / 2; 

    if (allowed_slots == 0) allowed_slots = 1; // I == I_min 일 때의 예외 처리

    // choose random slot
    random_slot_choice = call Random.rand32() % allowed_slots;

    // map slot index by level
    if (current_level % 2 == 0) {
      // even level -> slot 0,2,4,...
      target_slot_index = random_slot_choice * 2;
    } else {
      // odd level -> slot 1,3,5,...
      target_slot_index = random_slot_choice * 2 + 1;
    }

    // random offset within slot
    offset = call Random.rand32() % slot_size;
    gt_tx = gt_start + I_half + (target_slot_index * slot_size) + offset;
    
    if (gt < gt_tx) {
      timer_state = STATE_WAIT_TX;
      delay = gt_tx - gt;
    } else {
      timer_state = STATE_WAIT_BOUNDARY;
      delay = gt_end - gt;
    }
    
    call AlignedTimer.startOneShot(delay);
  }

  command error_t StdControl.start() {
    is_running = TRUE;
    memset(&current_cmd, 0, sizeof(cmd_msg_t));
    reset_aligned_timer();
    return SUCCESS;
  }

  command error_t StdControl.stop() {
    is_running = FALSE;
    call AlignedTimer.stop();
    return SUCCESS;
  }
  
  command void DisseminationUpdate.change(cmd_msg_t* newVal) {
    if (!is_running) return;
    current_seq++; // update version
    memcpy(&current_cmd, newVal, sizeof(cmd_msg_t));

    apply_trickle_config();
    
    // trickle reset (I = I_min)
    current_I = a2_i_min;
    c_counter = 0;
    timer_state = STATE_WAIT_BOUNDARY;
    reset_aligned_timer();
  }

  command const cmd_msg_t* DisseminationValue.get() {
    return &current_cmd;
  }

  command void DisseminationValue.set(const cmd_msg_t* val) {
    memcpy(&current_cmd, val, sizeof(cmd_msg_t));
  }

  event void AlignedTimer.fired() {
    if (timer_state == STATE_WAIT_TX) {
      // transmit time reached. check adaptive suppression
      bool bypass_suppression = (dependent_neighbors > 0);
      if ((c_counter < a2_k_threshold || bypass_suppression) && !radio_busy) {
        a2_trickle_msg_t* payload = (a2_trickle_msg_t*)call TrickleSend.getPayload(&pkt, sizeof(a2_trickle_msg_t));
        if (payload != NULL) {
          payload->seq_num = current_seq;
          payload->sender_id = TOS_NODE_ID;
          memcpy(&(payload->cmd), &current_cmd, sizeof(cmd_msg_t));

          if (call TrickleSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(a2_trickle_msg_t)) == SUCCESS) {
            radio_busy = TRUE;
          }
        }
      }
      // wait for next boundary
      reset_aligned_timer();
      
    } else {
      // boundary reached. expand interval
      if (current_I < a2_i_max) {
        current_I *= 2;
        if (current_I > a2_i_max) current_I = a2_i_max;
      }
      c_counter = 0;
      reset_aligned_timer();
    }
  }

  event message_t* TrickleReceive.receive(message_t* msg, void* payload, uint8_t len) {
    if (len == sizeof(a2_trickle_msg_t)) {
      a2_trickle_msg_t* rx = (a2_trickle_msg_t*)payload;

      if (rx->seq_num == current_seq) {
        // same version: increment suppression counter
        c_counter++;
      } 
      else if (rx->seq_num > current_seq) {
        // new version: update state and notify
        current_seq = rx->seq_num;
        memcpy(&current_cmd, &(rx->cmd), sizeof(cmd_msg_t));

        apply_trickle_config();

        current_I = a2_i_min;
        c_counter = 0;
        reset_aligned_timer();
        signal DisseminationValue.changed(); 
      } 
      else {
        // old version: minimize interval to update neighbors
        current_I = a2_i_min;
        reset_aligned_timer();
      }
    }
    return msg;
  }

  event void TrickleSend.sendDone(message_t* msg, error_t error) {
    radio_busy = FALSE;
  }
}