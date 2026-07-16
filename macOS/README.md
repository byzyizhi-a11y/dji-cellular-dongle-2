# macOS Support

This folder contains research and  macOS supported for the DJI Cellular Dongle 2.

## Current Status

The DJI Cellular Dongle 2 is detected by macOS as a USB composite device (VID 0x2CA3, PID 0x4009), but no `/dev/cu.*` serial device is created because all interfaces are vendor-specific (USB Class 0xFF).

The objective is to expose Interface **MI_03** as a standard serial port through USBSerialDriverKit and use `pppd` for PPP networking.

## Confirmed Hardware

- Cellular Module: Fibocom NL668T-GL
- Firmware: 19906.5090.00.02.00.23

Confirmed PPP interface:

| Item | Value |
|------|-------|
| Interface | MI_03 |
| Bulk IN | 0x86 |
| Bulk OUT | 0x04 |
| Interrupt IN | 0x87 |

Linux testing confirms that:

```
ATD*99***1#
```

returns:

```
CONNECT
```

## Planned Architecture

```
DJI Cellular Dongle 2
        │
        ▼
USB Interface MI_03
        │
        ▼
USBSerialDriverKit
        │
        ▼
   /dev/ttyd001
        │
        ▼
pppd
        │
        ▼
PPP Network
```

## Development Checklist

- [x] USB device detected by macOS
- [x] Internal modem identified
- [x] PPP interface confirmed on Linux
- [x] macOS includes pppd
- [x] Create Xcode project
- [x] Match Interface MI_03
- [ ] Send AT
- [ ] Receive OK
- [ ] Expose /dev/cu.DJICellular2
- [ ] Establish PPP connection

## Driver Matching

Target only:

- Vendor ID: 0x2CA3
- Product ID: 0x4009
- Interface Number: 3

## Testing

```
screen /dev/ttyd001 115200
```

Then test:

```
AT
ATI
AT+CPIN?
AT+CEREG?
ATD*99***1#
```

Result:

```
CONNECT
```

## Notes

- Native macOS Cellular integration is not implemented.
- The initial goal is a working USB serial device and PPP connection.
- This project is experimental and unofficial.

## Disclaimer

This project is not affiliated with DJI, Fibocom or Apple.
