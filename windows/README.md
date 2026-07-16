# Windows Support

This folder contains research and experimental Windows support for the DJI Cellular Dongle 2.

## Current Status

The device exposes five USB interfaces:

| Interface | Status |
|-----------|--------|
| MI_00 | Qualcomm WWAN interface candidate |
| MI_01 | Unknown / auxiliary |
| MI_02 | AT command serial port |
| MI_03 | PPP dial-up serial port |
| MI_04 | Windows supports internet port |

## Confirmed Hardware

- USB VID: `0x2CA3`
- USB PID: `0x4009`
- Product: `Baiwang`
- Internal modem: **Fibocom NL668T-GL**

## Working Features

### AT Commands

`MI_02` can be bound to the DJI USB Virtual COM driver and used for AT commands.

Example:

```
AT
ATI
AT+CPIN?
AT+CEREG?
```

### DJI Cellular Dongle 1 driver

`MI_04` can be manually installed with the DJI Cellular Dongle 1 driver.

Windows recognizes:Quectel Wireless Ethernet Adapter

And it can be used as the Mobile data in Windows

Therefore, native Windows Mobile Broadband is currently available.

## PPP Dial-up

Linux testing confirmed that `MI_03` accepts:

```
ATD*99***1#
```

and returns:

```
CONNECT
```

The planned Windows workflow is:

```
MI_03
    ↓
USB Virtual COM
    ↓
Standard Modem
    ↓
RAS / PPP
    ↓
Internet
```

## Research Goals

- [x] AT port working
- [x] Qualcomm WWAN driver loaded
- [x] PPP interface identified
- [ ] Install MI_03 as COM port
- [ ] Create Windows PPP connection
- [ ] Verify Internet access
- [ ] Investigate native WWAN support

## Notes

Native Windows "Cellular" support requires more than a network driver. It also needs proper WWAN/MBN integration, which appears to be missing from the DJI-specific firmware or driver package.

At present, PPP over the serial interface is considered the most practical Windows solution.

## Disclaimer

This project is unofficial and is not affiliated with DJI, Fibocom.
