#include "A2Trickle.h"
#include "WSN.h"

configuration A2TrickleC {
  provides {
    interface StdControl;
    interface DisseminationUpdate<cmd_msg_t>;
    interface DisseminationValue<cmd_msg_t>;
  }
}
implementation {
  components A2TrickleP;
  components new AMSenderC(AM_CMD_MSG) as TrickleSender;
  components new AMReceiverC(AM_CMD_MSG) as TrickleReceiver;
  components new TimerMilliC() as AlignedTimer;
  components TimeSyncC;

  components RandomC;
  components CollectionC;
  components LocalTimeMilliC;
  
  StdControl = A2TrickleP;
  DisseminationUpdate = A2TrickleP;
  DisseminationValue = A2TrickleP;
  
  A2TrickleP.TrickleSend -> TrickleSender;
  A2TrickleP.TrickleReceive -> TrickleReceiver;
  A2TrickleP.AlignedTimer -> AlignedTimer;
  A2TrickleP.GlobalTime -> TimeSyncC.GlobalTime;

  A2TrickleP.Random -> RandomC;
  A2TrickleP.CtpInfo -> CollectionC;
  A2TrickleP.Intercept -> CollectionC.Intercept[AM_REPORT_MSG];
  A2TrickleP.LocalTime -> LocalTimeMilliC;
}