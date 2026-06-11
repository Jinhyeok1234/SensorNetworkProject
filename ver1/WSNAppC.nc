#include "WSN.h"

configuration WSNAppC {}
implementation {
  components MainC, LedsC, WSNC as App;
  
  components ActiveMessageC;
  components SerialActiveMessageC;
  
  components CC2420ControlC;
  components CC2420ActiveMessageC;
  
  // Radio for command packet
  components new AMSenderC(AM_CMD_MSG) as RadioCmdSender;
  components new AMReceiverC(AM_CMD_MSG) as RadioCmdReceiver;
  
  // Radio for response packet
  components new AMSenderC(AM_RES_MSG) as RadioResSender;
  components new AMReceiverC(AM_RES_MSG) as RadioResReceiver;
  
  // Radio for report packet
  components new AMSenderC(AM_REPORT_MSG) as RadioReportSender;
  components new AMReceiverC(AM_REPORT_MSG) as RadioReportReceiver;
  
  // Serial communication
  components new SerialAMSenderC(AM_RES_MSG) as SerialResSender;
  components new SerialAMReceiverC(AM_CMD_MSG) as SerialCmdReceiver;
  components new SerialAMSenderC(AM_REPORT_MSG) as SerialReportSender;
  
  // Sensors
  components new VoltageC();
  components new SensirionSht11C() as TempSensor;
  components new HamamatsuS1087ParC() as LightSensor;
  
  // Timer
  components new TimerMilliC() as DataTimer;

  // =================================================

  App.Boot -> MainC.Boot;
  App.Leds -> LedsC;
  
  App.RadioControl -> ActiveMessageC;
  App.SerialControl -> SerialActiveMessageC;

  App.RadioPacket -> ActiveMessageC;
  App.SerialPacket -> SerialActiveMessageC;
  
  // Radio for command packet
  App.RadioCmdSend -> RadioCmdSender;
  App.RadioCmdReceive -> RadioCmdReceiver;
  
  // Radio for response packet
  App.RadioResSend -> RadioResSender;
  App.RadioResReceive -> RadioResReceiver;
  
  // Radio for report packet
  App.RadioReportSend -> RadioReportSender;
  App.RadioReportReceive -> RadioReportReceiver;
  
  // Serial communication
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
}