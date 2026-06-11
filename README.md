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