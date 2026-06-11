#include "WSN.h"

configuration WSNAppC {}
implementation {
  components MainC, LedsC, WSNC as App;
  
  components ActiveMessageC;
  components SerialActiveMessageC;
  
  components CC2420ControlC;
  components CC2420ActiveMessageC;

  // A^2 Trickle
  components A2TrickleC as CmdDiss;
  components RandomC;
  
  // CTP
  components CollectionC;
  components new CollectionSenderC(COL_CTP_RES) as CtpResSender;
  components new CollectionSenderC(COL_CTP_REPORT) as CtpReportSender;

  // Serial communication
  components new SerialAMSenderC(COL_CTP_RES) as SerialResSender;
  components new SerialAMReceiverC(AM_CMD_MSG) as SerialCmdReceiver;
  components new SerialAMSenderC(COL_CTP_REPORT) as SerialReportSender;
  
  // Sensors
  components new VoltageC();
  components new SensirionSht11C() as TempSensor;
  components new HamamatsuS1087ParC() as LightSensor;
  
  // Timer
  components new TimerMilliC() as DataTimer;
  components TimeSyncC;
  components LocalTimeMilliC;

  // =================================================

  App.Boot -> MainC.Boot;
  App.Leds -> LedsC;
  
  App.RadioControl -> ActiveMessageC;
  App.SerialControl -> SerialActiveMessageC;

  App.CtpPacket -> CollectionC.Packet;
  App.SerialPacket -> SerialActiveMessageC;

  // A^2 Trickle
  App.DisseminationControl -> CmdDiss.StdControl;
  App.CmdUpdate -> CmdDiss.DisseminationUpdate;
  App.CmdValue -> CmdDiss.DisseminationValue;

  // CTP
  App.RoutingControl -> CollectionC;
  App.RootControl -> CollectionC;
  App.CtpInfo -> CollectionC;
  App.PacketAcknowledgements -> ActiveMessageC;

  App.CtpResSend -> CtpResSender;
  App.CtpResReceive -> CollectionC.Receive[COL_CTP_RES];
  
  App.CtpReportSend -> CtpReportSender;
  App.CtpReportReceive -> CollectionC.Receive[COL_CTP_REPORT];
  
  // Serial Communication
  App.SerialResSend -> SerialResSender;
  App.SerialCmdReceive -> SerialCmdReceiver;
  App.SerialReportSend -> SerialReportSender;

  // Sensors
  App.VoltageRead -> VoltageC;
  App.TempRead -> TempSensor.Temperature;
  App.HumidityRead -> TempSensor.Humidity;
  App.LightRead -> LightSensor;
  
  // Config (channel, tx power)
  App.CC2420Config -> CC2420ControlC;
  App.CC2420Packet -> CC2420ActiveMessageC.CC2420Packet;
  
  // Timer
  App.DataTimer -> DataTimer;
  App.GlobalTime -> TimeSyncC;
  App.LocalTime -> LocalTimeMilliC;
}