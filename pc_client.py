import cmd
import serial
import threading
import struct
import logging
import sys
try:
    import readline
except ImportError:
    readline = None

class PromptAwareHandler(logging.StreamHandler):
    def __init__(self, stream=None, client=None):
        logging.StreamHandler.__init__(self, stream)
        self.client = client

    def emit(self, record):
        try:
            msg = self.format(record)
            sys.stdout.write('\r\033[K')
            sys.stdout.write(msg + '\n')
            
            if (self.client is None or self.client.is_running) and threading.current_thread().name != 'MainThread':
                sys.stdout.write('wsn> ')
                if readline:
                    sys.stdout.write(readline.get_line_buffer())
            sys.stdout.flush()
        except Exception:
            self.handleError(record)

class AMType:
    CMD_MSG = 0x10
    RES_MSG = 0x11
    REPORT_MSG = 0x20
    CTP_RES = 0x31
    CTP_REPORT = 0x32

class NodeID:
    BASE_STATION = 0x00

class CommandType:
    GET = 0x01
    SET = 0x02

class TargetCommand:
    LED = 0x01
    VOLTAGE = 0x02
    TEMP = 0x03
    CHANNEL = 0x04
    TX_POWER = 0x05
    LIGHT = 0x06
    HUMIDITY = 0x07
    REPORT = 0x08
    INTERVAL = 0x09
    TRICKLE_I_MIN = 0x10
    TRICKLE_I_MAX = 0x11
    TRICKLE_K     = 0x12

    @classmethod
    def get_name(cls, value):
        for k, v in cls.__dict__.items():
            if v == value:
                return k
        return "UNKNOWN"

    @classmethod
    def get_mask_targets(cls, mask):
        targets = []
        for i in range(7):
            if mask & (1 << i):
                targets.append(i + 1) # LED=1, VOLTAGE=2 ... 
        return targets

class WSNClient(cmd.Cmd):
    prompt = 'wsn> '
    intro = 'WSN Interactive Client Started. Type "help" for commands.'

    def __init__(self, port, baudrate):
        cmd.Cmd.__init__(self)
        self.port = port
        self.baudrate = baudrate
        self.serial_conn = None
        self.rx_thread = None
        self.is_running = False
        self.topology = {}
        self.logger = logging.getLogger("WSNClient")
        self._setup_logger()

    def _setup_logger(self):
        self.logger.setLevel(logging.INFO)
        # self.logger.setLevel(logging.DEBUG)
        formatter = logging.Formatter('[%(asctime)s][%(levelname)s] %(message)s', '%Y-%m-%d %H:%M:%S')
        
        console_handler = PromptAwareHandler(sys.stdout, self)
        console_handler.setFormatter(formatter)
        self.logger.addHandler(console_handler)
        
        file_handler = logging.FileHandler('wsn_client.log')
        file_handler.setFormatter(formatter)
        self.logger.addHandler(file_handler)

    def start(self):
        try:
            self.serial_conn = serial.Serial(self.port, self.baudrate, timeout=1)
            self.is_running = True
            self.rx_thread = threading.Thread(target=self._rx_loop)
            self.rx_thread.daemon = True
            self.rx_thread.start()
            self.logger.info("Connected to %s at %d baud.", self.port, self.baudrate)
            self.cmdloop()
        except serial.SerialException as e:
            self.logger.error("Failed to connect to %s: %s", self.port, e)
        finally:
            self.stop()

    def stop(self):
        self.is_running = False
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.close()
        self.logger.info("Disconnected.")

    def _crc_byte(self, crc, b):
        crc = crc ^ (b << 8)
        for _ in range(8):
            if crc & 0x8000:
                crc = (crc << 1) ^ 0x1021
            else:
                crc = crc << 1
            crc = crc & 0xFFFF
        return crc

    def _send_serial_frame(self, am_id, payload):
        if not self.serial_conn or not self.serial_conn.is_open:
            self.logger.error("Serial connection not active.")
            return

        frame = bytearray()
        frame.append(0x45)
        frame.append(0x00)
        frame.append(0xFF)
        frame.append(0xFF)
        frame.append(0x00)
        frame.append(0x00)
        frame.append(len(payload))
        frame.append(0x00)
        frame.append(am_id)
        frame.extend(payload)

        crc = 0
        for b in frame:
            crc = self._crc_byte(crc, b)

        hdlc_frame = bytearray([0x7E])
        
        crc_low = crc & 0xFF
        crc_high = (crc >> 8) & 0xFF
        
        for b in list(frame) + [crc_low, crc_high]:
            if b == 0x7E or b == 0x7D:
                hdlc_frame.append(0x7D)
                hdlc_frame.append(b ^ 0x20)
            else:
                hdlc_frame.append(b)

        hdlc_frame.append(0x7E)
        self.serial_conn.write(hdlc_frame)

    def _rx_loop(self):
        in_frame = False
        escape = False
        buffer = bytearray()

        while self.is_running and self.serial_conn:
            try:
                b_raw = self.serial_conn.read(1)
                if not b_raw:
                    continue
                b = ord(b_raw)

                if b == 0x7E:
                    if in_frame and len(buffer) > 0:
                        self._process_frame(buffer)
                    buffer = bytearray()
                    in_frame = True
                    escape = False
                elif b == 0x7D:
                    escape = True
                else:
                    if escape:
                        b = b ^ 0x20
                        escape = False
                    if in_frame:
                        buffer.append(b)
            except Exception as e:
                if self.is_running:
                    self.logger.error("RX Loop Error: %s", e)

    def _format_led(self, value):
        b_val = (value >> 2) & 0x01
        g_val = (value >> 1) & 0x01
        r_val = value & 0x01
        
        colors = ""
        if b_val: colors += "B"
        if g_val: colors += "G"
        if r_val: colors += "R"
        
        if not colors: colors = "Off"
        
        return "%d%d%d (%s)" % (b_val, g_val, r_val, colors)

    def _convert_and_format_value(self, target_cmd, value, show_raw=False, is_report=False):
        raw_str = " (Raw: %d)" % value if show_raw else ""
        
        if target_cmd == TargetCommand.VOLTAGE:
            converted_v = (value / 4096.0) * 3.0
            if is_report: return "battery: %.3f V" % converted_v
            return "%.3f V%s" % (converted_v, raw_str)
            
        elif target_cmd == TargetCommand.TEMP:
            converted_t = -39.6 + 0.01 * value
            if is_report: return "T: %.2f C" % converted_t
            return "%.2f C%s" % (converted_t, raw_str)
            
        elif target_cmd == TargetCommand.HUMIDITY:
            converted_h = -4.0 + 0.0405 * value - 0.0000028 * (value * value)
            if is_report: return "hum: %.2f %%RH" % converted_h
            return "%.2f %%RH%s" % (converted_h, raw_str)
            
        elif target_cmd == TargetCommand.LIGHT:
            converted_l = 6.25 * (1.5 / 4096.0 * value)
            if is_report: return "light: %.2f lx" % converted_l
            return "%.2f Lux%s" % (converted_l, raw_str)
            
        elif target_cmd == TargetCommand.LED:
            led_str = self._format_led(value)
            if is_report: return "LED: %s" % led_str
            return "%s%s" % (led_str, raw_str)
            
        elif target_cmd == TargetCommand.CHANNEL:
            if is_report: return "ch: %d" % value
            return "%d%s" % (value, raw_str)
            
        elif target_cmd == TargetCommand.TX_POWER:
            if is_report: return "tx: %d" % value
            return "%d%s" % (value, raw_str)
            
        elif target_cmd == TargetCommand.REPORT:
            mask_str = "0b{0:07b} ({0})".format(value)
            active_targets = TargetCommand.get_mask_targets(value)
            target_names = [TargetCommand.get_name(t) for t in active_targets]
            if target_names:
                return "%s -> [%s]" % (mask_str, ", ".join(target_names))
            else:
                return "%s -> [NONE]" % mask_str
                
        elif target_cmd == TargetCommand.INTERVAL:
            return "%d ms" % value
            
        else:
            return "%d%s" % (value, raw_str)

    def _process_frame(self, frame):
        if len(frame) == 0:
            return
                    
        if frame[0] != 0x45:
            self.logger.debug("Non-AM packet dropped. Protocol byte: 0x%02X", frame)
            return
            
        if len(frame) < 10:
            self.logger.debug("Frame too short: len=%d", len(frame))
            return
            
        am_id = frame[8]
        payload_len = frame[6]
        payload = frame[9:9+payload_len]
        
        frame_hex = " ".join(["%02X" % b for b in frame])
        self.logger.debug("RAW FRAME (AM:%d, Len:%d): %s", am_id, payload_len, frame_hex)

        if am_id == AMType.RES_MSG or am_id == AMType.CTP_RES:
            if len(payload) >= 11:
                node_id, seq_num, timestamp, target_cmd, value = struct.unpack(">HHIBH", str(payload[:11]))
                target_name = TargetCommand.get_name(target_cmd)
                val_str = self._convert_and_format_value(target_cmd, value, show_raw=True)
                self.logger.info("[Node %d][Seq:%d] %s: %s", node_id, seq_num, target_name, val_str)
            else:
                self.logger.error("Invalid payload length for AM 11")
                
        elif am_id == AMType.REPORT_MSG or am_id == AMType.CTP_REPORT:
            if len(payload) >= 13:
                node_id, seq_num, timestamp, parent_id, etx, setting = struct.unpack(">HHIHHB", payload[:13])
                
                # update network topology
                if parent_id != 0xFFFF:
                    self.topology[node_id] = parent_id

                # save ETX (
                self.etx_table = getattr(self, 'etx_table', {}) # initialize
                self.etx_table[node_id] = etx

                active_targets = TargetCommand.get_mask_targets(setting)
                num_values = len(active_targets)
                expected_len = 13 + num_values * 2
                
                if len(payload) >= expected_len:
                    values = struct.unpack(">" + "H" * num_values, str(payload[13:expected_len])) if num_values > 0 else ()
                    
                    target_values = {}
                    for i in range(num_values):
                        target_values[active_targets[i]] = values[i]
                        
                    ordered_targets = [
                        TargetCommand.TEMP,
                        TargetCommand.HUMIDITY,
                        TargetCommand.LIGHT,
                        TargetCommand.LED,
                        TargetCommand.CHANNEL,
                        TargetCommand.TX_POWER,
                        TargetCommand.VOLTAGE
                    ]
                    
                    report_strs = []
                    for t_cmd in ordered_targets:
                        if t_cmd in target_values:
                            val_str = self._convert_and_format_value(t_cmd, target_values[t_cmd], is_report=True)
                            report_strs.append(val_str)
                            
                    if not report_strs:
                        report_strs.append("NO DATA (Mask: 0)")
                        
                    self.logger.info("[Node %d][Seq:%d][ETX: %d] REPORT: %s", node_id, seq_num, etx, " | ".join(report_strs))
                else:
                    self.logger.error("Invalid payload length for AM 20")

    def _parse_target(self, target_str):
        target_str = target_str.lower()
        if target_str == "led": return TargetCommand.LED
        if target_str in ("voltage", "v", "volt", "battery", "batt", "b"): return TargetCommand.VOLTAGE
        if target_str in ("temperature", "t", "temp"): return TargetCommand.TEMP
        if target_str in ("humidity", "h", "hum"): return TargetCommand.HUMIDITY
        if target_str in ("light", "l"): return TargetCommand.LIGHT
        if target_str in ("channel", "ch", "chan"): return TargetCommand.CHANNEL
        if target_str in ("tx_power", "tx-power", "txp", "tx"): return TargetCommand.TX_POWER
        if target_str in ("report", "rep"): return TargetCommand.REPORT
        if target_str in ("interval", "int"): return TargetCommand.INTERVAL
        if target_str in ("trickle_i_min", "trickle_I_min", "i_min", "I_min"): return TargetCommand.TRICKLE_I_MIN
        if target_str in ("trickle_i_max", "trickle_I_max", "i_max", "I_max"): return TargetCommand.TRICKLE_I_MAX
        if target_str in ("trickle_k", "k"): return TargetCommand.TRICKLE_K
        return None

    def do_get(self, arg):
        args = arg.split()
        if len(args) < 1:
            self.logger.info("Usage: get [target]")
            self.logger.info("  [target] options (synonyms):")
            self.logger.info("    led           : led")
            self.logger.info("    voltage       : voltage, v, volt, battery, batt, b")
            self.logger.info("    temp          : temperature, t, temp")
            self.logger.info("    humidity      : humidity, h, hum")
            self.logger.info("    light         : light, l")
            self.logger.info("    channel       : channel, ch, chan")
            self.logger.info("    tx_power      : tx_power, tx-power, txp, tx")
            self.logger.info("    report        : report, rep")
            self.logger.info("    interval      : interval, int")
            self.logger.info("    trickle_i_min : trickle_I_min, i_min, I_min")
            self.logger.info("    trickle_i_max : trickle_I_max, i_max, I_max")
            self.logger.info("    trickle_k     : k")
            self.logger.info("  [node_id] default is all (Broadcast)")
            return

        target = self._parse_target(args[0])
        if target is None:
            self.logger.info("Unknown target.")
            return

        dest_node = 0xFFFF # default: AM_BROADCAST_ADDR
        if len(args) >= 2:
            try:
                dest_node = int(args[1], 0)
            except ValueError:
                self.logger.info("Invalid node ID. Must be an integer.")
                return

        payload = struct.pack(">BBHH", CommandType.GET, target, 0, dest_node)
        self._send_serial_frame(AMType.CMD_MSG, payload)

    def do_set(self, arg):
        args = arg.split()
        if len(args) < 2:
            self.logger.info("Usage: set [target] [value]")
            self.logger.info("  [target] options:")
            self.logger.info("    led           : 0~7 (3-bit: B,G,R)")
            self.logger.info("    interval      : Value in milliseconds (e.g., 5000 for 5s)")
            self.logger.info("    tx power      : 1~31")
            self.logger.info("    report        : 0~127 or 0x00~0x7F or 0b0000000~0b1111111")
            self.logger.info("                    Bit 0: LED, Bit 1: Voltage, Bit 2: Temp, Bit 3: Channel")
            self.logger.info("                    Bit 4: Tx_Power, Bit 5: Light, Bit 6: Humidity")
            self.logger.info("    trickle_i_min : Value in milliseconds (e.g., 5000 for 5s)")
            self.logger.info("    trickle_i_max : Value in milliseconds (e.g., 5000 for 5s)")
            self.logger.info("    trickle_k     : 1~")
            self.logger.info("  [node_id] default is all (Broadcast)")
            return

        target = self._parse_target(args[0])
        if target is None or target in {TargetCommand.VOLTAGE, TargetCommand.TEMP, TargetCommand.HUMIDITY, TargetCommand.LIGHT, TargetCommand.CHANNEL}:
            self.logger.info("Unknown target.")
            return

        try:
            value = int(args[1], 0)
        except ValueError:
            self.logger.info("Value must be an integer, hex (0x..), or binary (0b..).")
            return

        if target == TargetCommand.LED and (value<0 or value>8):
            self.logger.info("Value for LED must be in 0~7.")
            return
        if target == TargetCommand.TX_POWER and (value<1 or value>31):
            self.logger.info("Value for tx power must be in 1~31.")
            return
        if target == TargetCommand.REPORT and (value<0 or value>127):
            self.logger.info("Value for report must be in 0~127.")
            return
        if target == TargetCommand.TRICKLE_K and value<1:
            self.logger.info("Value for Trickle's k must be larger than 0.")
            return

        dest_node = 0xFFFF # default: AM_BROADCAST_ADDR
        if len(args) >= 3:
            try:
                dest_node = int(args[2], 0)
            except ValueError:
                self.logger.info("Invalid node ID. Must be an integer.")
                return

        payload = struct.pack(">BBHH", CommandType.SET, target, value, dest_node)
        self._send_serial_frame(AMType.CMD_MSG, payload)

    def do_tree(self, arg):
        if not self.topology:
            self.logger.info("No topology data available yet.")
            return

        # group childs by their parent
        tree = {}
        for child, parent in self.topology.items():
            if parent not in tree:
                tree[parent] = []
            tree[parent].append(child)

        def print_tree(node, prefix="", is_last=True, is_root=True):
            etx_val = self.etx_table.get(node, 0) if node != 0 else 0

            if is_root:
                self.logger.info("- Node %d [ETX: %d]", node, etx_val)
                next_prefix = " "
            else:
                branch = "L-- " if is_last else "|-- "
                self.logger.info("%s%sNode %d [ETX: %d]", prefix, branch, node, etx_val)
                next_prefix = prefix + ("    " if is_last else "|   ")

            children = tree.get(node, [])
            for i, child in enumerate(children):
                print_tree(child, next_prefix, i == len(children) - 1, False)

        self.logger.info("--- Current Network Topology ---")
        # print recursively from Base Station(0). If 0 doesn't exist, print individual nodes
        if 0 in tree or 0 in self.topology:
            print_tree(0)
        else:
            self.logger.info("Base Station not found in topology data. Raw data: %s", self.topology)
        self.logger.info("--------------------------------")

    def do_exit(self, arg):
        return True

    def help_get(self):
        self.do_get("")

    def help_set(self):
        self.do_set("")

    def help_tree(self):
        self.logger.info("Usage: tree")
        self.logger.info("  Shows the current routing topology (DODAG) based on parent IDs.")

    def help_exit(self):
        self.logger.info("Usage: exit")
        self.logger.info("  Terminates the client and closes the serial connection.")

if __name__ == "__main__":
    client = WSNClient(port="/dev/ttyUSB0", baudrate=115200)
    client.start()