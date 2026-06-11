# SensorNetworkProject

## 1. Experimental Environment

- Software Environment
  - OS (Desktop): Ubuntu 20.04.6 LTS (WSL in Windows 11)
  - OS (Mote): TinyOS 2.x
  - Core-tree: Oct 2025, Commit a59dd13
  - Language: nesC (nescc 1.4.0)
  - Compiler: msp430-gcc 4.6.3 (LTS 20120406)

- Hardware Environment
  - Mote: TelosB (Kmote)

- Python Dependencies
  - Required Library: `pyserial` (Verified version for this environment: 3.5)
  - Installation Method 1 (Using `requirements.txt`):
    ```bash
    pip install -r requirements.txt
    ```
  - Installation Method 2 (Standalone installation):
    ```bash
    pip install pyserial==3.5
    ```

## 2. Usage Instructions

- Windows PowerShell (Administrator) - USB Device Connection
  - List connected USB devices:
    ```powershell
    usbipd list
    ```
  - Bind the specific USB device:
    ```powershell
    usbipd bind --busid [BUSID]
    ```
  - Attach the bound USB device to WSL Ubuntu:
    ```powershell
    usbipd attach --wsl --busid [BUSID]
    ```

- Ubuntu (WSL) - Build and Install Program on Mote
  - Compile source code and upload to the node (replace `[node id]` with the target node number):
    ```bash
    make telosb install,[node id] bsl,/dev/ttyUSB0
    ```
  - Note: The Base Station node ID must be fixed to `0`.

- User Interface Execution
  - Run the monitoring interface:
    ```bash
    python2 msg_monitor.py
    ```
  - Check commands: Enter `help` after the prompt starts to view available commands.

## 3. Interactive Client Commands

Once the client is running, you will see a `wsn> ` prompt. The following commands are available:

### `get [target] [node_id]`
Retrieves the current value of the specified target from the node(s).
- `[node_id]`: (Optional) Target node ID. Default is broadcast (all nodes).
- `[target]` options (and synonyms):
  - `led`
  - `voltage` (v, volt, battery, batt, b)
  - `temp` (temperature, t)
  - `humidity` (h, hum)
  - `light` (l)
  - `channel` (ch, chan)
  - `tx_power` (tx-power, txp, tx)
  - `report` (rep)
  - `interval` (int)
  - `trickle_i_min` (trickle_I_min, i_min, I_min)
  - `trickle_i_max` (trickle_I_max, i_max, I_max)
  - `trickle_k` (k)

### `set [target] [value] [node_id]`
Sets a new value for the specified target. The `[target]` synonyms are identical to the `get` command.
- `[node_id]`: (Optional) Target node ID. Default is broadcast (all nodes).
- `[target]` & `[value]` specifications:
  - `led`: `0~7` (3-bit value for B, G, R).
  - `interval`: Periodic report interval in milliseconds (e.g., `5000` for 5s).
  - `tx_power`: `1~31`.
  - `report`: `0~127` (or `0x00~0x7F`, `0b0000000~0b1111111`). Defines the data included in the periodic report.
    - Bit 0: LED, Bit 1: Voltage, Bit 2: Temp, Bit 3: Channel
    - Bit 4: Tx_Power, Bit 5: Light, Bit 6: Humidity
  - `trickle_i_min`: Minimum timeslot size for Trickle timer in milliseconds (*Only supported in the root folder version; not available in ver 1 or ver 2*).
  - `trickle_i_max`: Maximum timeslot size for Trickle timer in milliseconds (*Only supported in the root folder version*).
  - `trickle_k`: `1~`. Trickle algorithm redundancy parameter (*Only supported in the root folder version*).

### `tree`
Shows the current routing topology (DODAG) based on parent IDs.
- Note: This tree topology is dynamically generated and updated only when report packets are received from sensor nodes.

### `help [command]`
Displays help information. Type `help` to list all available commands, or `help [command]` for detailed usage of a specific command.

### `exit`
Terminates the client and closes the serial connection.
- Note: The client can also be terminated at any time using `Ctrl+C`.