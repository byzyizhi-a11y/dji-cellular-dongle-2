# DJI Cellular Dongle 2 Research

Experimental computer support and reverse-engineering notes for the DJI Cellular Dongle 2.

## Confirmed hardware

- USB VID: `2CA3`
- USB PID: `4009`
- USB product string: `Baiwang`
- Cellular module: Fibocom `NL668T-GL`
- Firmware: `19906.5090.00.02.00.23`

## Current status

| Platform | Status |
|---|---|
| Linux | PPP connection working through USB serial |
| Windows | AT serial and WWAN adapter detected |
| macOS | USB device detected; USB serial DriverKit support planned |

## Confirmed interfaces

| Interface | Purpose |
|---|---|
| MI_00 | Qualcomm WWAN/QMI data interface candidate |
| MI_02 | AT command port |
| MI_03 | PPP dial-up port |
| MI_04 | Windows native Mobile data interface |

## Linux

```bash
sudo ./linux/dji4g.sh setup
sudo ./linux/dji4g.sh start
./linux/dji4g.sh status
./linux/dji4g.sh test
