# DJI Cellular Dongle 2（大疆 4G 模块 2 代）电脑使用研究记录

更新时间：2026-07-15

## 1. 研究对象

- 产品：DJI Cellular Dongle 2 / 大疆增强图传模块 2
- USB VID：`0x2CA3`
- USB PID：`0x4009`
- USB 版本：2.0 High-Speed（480 Mbit/s）
- USB 字符串：Manufacturer `BAIWANG`，Product `Baiwang`
- USB 配置：1 个 Configuration，5 个 Interface
- 最大电流：500 mA

内部蜂窝模组已经通过 AT 命令确认：

```text
Manufacturer: Fibocom Wireless Inc.
Model: NL668T-GL
Revision: 19906.5090.00.02.00.23
ESN: +GSN: 0x0
+GCAP: +CGSM
```

公开日志或截图时应遮挡 IMEI、ICCID、IMSI 等唯一标识。

## 2. 已确认的蜂窝状态

AT 控制口正常，SIM、LTE 注册和 PDP 会话均正常：

```text
AT+CPIN?
+CPIN: READY
OK

AT+CEREG?
+CEREG: 0,1
OK

AT+CGREG?
+CGREG: 0,1
OK

AT+COPS?
+COPS: 0,2,"46011",7
OK

AT+CGATT?
+CGATT: 1
OK

AT+CGACT?
+CGACT: 1,1
OK
```

其中 `46011` 为中国电信，`7` 表示 LTE/E-UTRAN。

CID 1 已获得 IPv4/IPv6 地址：

```text
AT+CGPADDR=1
+CGPADDR: 1,"10.69.64.192","..."
```

USB/网络相关状态：

```text
AT+GTUSBMODE?
+GTUSBMODE: 30

AT+GTRNDIS?
+GTRNDIS: 0

AT+GTAUTOCONNECT?
+GTAUTOCONNECT: 0
```

尝试 `AT+GTRNDIS=1,1` 返回 `ERROR`。结论是当前 DJI 定制固件/Profile 30 不允许或不支持通过该命令启用 RNDIS。

## 3. USB 接口结构

### MI_00

```text
Class/SubClass/Protocol: FF/FF/FF
Bulk IN  0x81
Bulk OUT 0x01
```

只有一对 Bulk 端点，没有 Interrupt IN，也没有 CDC functional descriptor。Windows 下可强制绑定 Qualcomm WWAN 驱动。

### MI_01

```text
Class/SubClass/Protocol: FF/00/00
Interrupt IN 0x83
Bulk IN      0x82
Bulk OUT     0x02
```

带 CDC 风格的 `0x24` functional descriptors。

### MI_02

```text
Class/SubClass/Protocol: FF/00/00
Interrupt IN 0x85
Bulk IN      0x84
Bulk OUT     0x03
```

已确认：

- Windows 的 DJI INF 将其绑定到 `usbser.sys`
- 设备名为 `DEVICE USB Virtual COM`
- 可发送 AT 命令
- 是主要 AT 控制口

### MI_03

```text
Class/SubClass/Protocol: FF/00/00
Interrupt IN 0x87
Bulk IN      0x86
Bulk OUT     0x04
```

已确认：

- Linux 中绑定为 `/dev/ttyUSB3`
- 可响应 `AT`
- 执行 `ATD*99***1#` 返回 `CONNECT`
- 是可用的 PPP 拨号口

### MI_04

```text
Class/SubClass/Protocol: FF/FF/FF
Interrupt IN 0x89
Bulk IN      0x88
Bulk OUT     0x05
```

用途尚未完全确认，较可能是诊断/私有接口。

## 4. 当前接口映射结论

| USB 接口 | 当前结论 | 可信度 |
|---|---|---:|
| MI_00 | Qualcomm 私有 WWAN/QMI 数据接口候选 | 高 |
| MI_01 | 辅助串口/NMEA/Modem 类接口 | 中 |
| MI_02 | AT 控制串口 | 已确认 |
| MI_03 | PPP 拨号串口 | 已确认 |
| MI_04 | 诊断/私有接口 | 中 |

## 5. Windows 研究结果

### 5.1 DJI 虚拟串口驱动

已安装 INF：

```text
C:\Windows\INF\oem57.inf
```

关键匹配项：

```ini
%DEVICEVCOM% = XP40, USB\VID_2CA3&PID_4009&MI_02
```

安装段：

```ini
NTMPDriver = usbser.sys
AddService = usbser
```

结论：DJI 确实为二代模块的 `MI_02` 提供了 VCOM 映射，但只负责串口，不负责其余接口或网络。

### 5.2 Qualcomm WWAN 驱动

已存在驱动：

```text
Qualcomm HS-USB WWAN Adapter
qcusbwwan.sys
Driver version: 4.0.6.5
NDIS: 6.20
```

将其强制安装到：

```text
USB\VID_2CA3&PID_4009&MI_00
```

结果：

```text
Status: OK
Class: Net
MediaType: Wireless WAN
```

`Get-NetAdapter` 可见 Qualcomm HS-USB WWAN Adapter，但状态为 Disconnected。

`netsh mbn show interfaces` 返回“没有任何移动宽带接口”。

结论：

- `qcusbwwan.sys` 能加载并创建旧式 NDIS WWAN 网卡
- 但没有向现代 Windows MBN/WWAN 平台注册可管理接口
- Windows 设置中的原生“手机网络”不能直接使用
- 可能缺少 Fibocom/DJI OEM 控制层、连接管理组件、特定 QMI 初始化或完整驱动包

### 5.3 Windows 可行方案

优先方案：MI_03 + USB VCOM + Windows RAS/PPP。

```text
MI_03
→ DEVICE USB Virtual COM
→ 标准调制解调器
→ 拨号号码 *99***1#
→ Windows PPP/RAS
```

该路线尚未在 Windows 完整完成，但 MI_03 的 PPP 拨号能力已在 Linux 中验证。

## 6. Ubuntu/Linux 研究结果

### 6.1 qmi_wwan 测试

执行：

```bash
modprobe qmi_wwan
echo 2ca3 4009 > /sys/bus/usb/drivers/qmi_wwan/new_id
```

后，Linux 将 MI_01～MI_04 都尝试绑定为 QMI，生成多个 `/dev/cdc-wdm*` 和 `wwan*`，但 `qmicli` 无法正常完成。

MI_00 单独绑定：

```bash
echo '1-1:1.0' > /sys/bus/usb/drivers/qmi_wwan/bind
```

返回 `No such device`。

结论：

- 主线 `qmi_wwan` 不接受 MI_00 的私有接口布局
- Windows 的 `qcusbwwan.sys` 能识别 MI_00，不代表 Linux 主线 `qmi_wwan` 可以直接使用
- 可能需要 Qualcomm GobiNet/Fibocom 专用驱动

### 6.2 Linux USB 串口绑定

使用：

```bash
modprobe option
echo 2ca3 4009 > /sys/bus/usb-serial/drivers/option1/new_id
```

成功产生：

```text
MI_00 → /dev/ttyUSB0
MI_01 → /dev/ttyUSB1
MI_02 → /dev/ttyUSB2
MI_03 → /dev/ttyUSB3
MI_04 → /dev/ttyUSB4
```

其中：

- `/dev/ttyUSB2`：AT 控制口
- `/dev/ttyUSB3`：PPP 拨号口

在 `/dev/ttyUSB3` 中执行：

```text
ATD*99***1#
```

返回 `CONNECT`。

### 6.3 Ubuntu 图形界面识别

NetworkManager/ModemManager 可以把设备识别为 GSM 调制解调器，观察到：

```text
ttyUSB2    GSM    已连接
```

原因：

1. Linux `option` 驱动先把 DJI 私有 USB 接口映射成 ttyUSB 串口
2. ModemManager 通过 AT 命令探测 SIM、注册状态、信号与数据能力
3. NetworkManager 创建 GSM/移动宽带连接
4. GNOME 设置显示“移动数据”

Ubuntu 不是通过 DJI VID/PID 识别产品，而是通过标准 AT 行为识别“这是一个蜂窝 Modem”。

## 7. macOS 研究结果

### 7.1 USB 识别

macOS 可以看到整个 USB 设备：

```text
Baiwang
VID: 0x2CA3
PID: 0x4009
Version: 3.18
```

但没有生成 `/dev/cu.usbmodem*` 或 `/dev/cu.usbserial*`。

原因：

- 五个接口都声明为 Vendor Specific (`Class FF`)
- macOS 没有 Linux `option new_id` 这种临时匹配机制
- Apple 自带串口驱动不会自动接管 MI_03

### 7.2 PPP 工具

macOS 中仍存在：

```text
/usr/sbin/pppd
```

缺少 `/etc/ppp/options` 时可创建：

```bash
sudo mkdir -p /etc/ppp
sudo touch /etc/ppp/options
```

### 7.3 macOS 可行方案

目标：

```text
VID 0x2CA3
PID 0x4009
MI_03
Bulk IN  0x86
Bulk OUT 0x04
Interrupt IN 0x87
→ USBSerialDriverKit
→ /dev/cu.DJICellular2
→ pppd
```

建议只匹配 MI_03，避免抢占其他接口。

最小实现顺序：

1. 创建 DriverKit App + DEXT
2. 让扩展成功安装
3. 只匹配 `2CA3:4009:MI_03`
4. 打开 USB Interface
5. 通过 Bulk OUT `0x04` 发送 `AT\r`
6. 从 Bulk IN `0x86` 收到 `OK`
7. 暴露 `/dev/cu.*`
8. 交给 `pppd`
9. 拨号 `*99***1#`

## 8. 为什么 Windows 原生“手机网络”比 PPP 难

PPP 只需要：

```text
串口
→ AT
→ ATD*99***1#
→ CONNECT
→ PPP
```

Windows 原生移动宽带还要求：

```text
USB WWAN 驱动
→ QMI/MBIM 控制面
→ SIM 管理
→ 运营商注册状态
→ APN 管理
→ WwanSvc
→ MBN API
→ 设置中的手机网络
```

目前已经实现的是：

```text
MI_00
→ qcusbwwan.sys
→ NDIS Wireless WAN Adapter
```

缺少的是 MBN/WWAN 控制层注册和管理。

## 9. 当前最实用的结论

### Linux

已经基本可用：

```text
option USB serial
→ ModemManager
→ NetworkManager
→ GSM/PPP
```

### Windows

最现实：

```text
MI_03
→ USB VCOM
→ 标准 Modem
→ RAS/PPP
```

原生手机网络仍需完整 Fibocom/DJI WWAN 驱动或进一步逆向。

### macOS

可行但需开发：

```text
USBSerialDriverKit
→ MI_03
→ /dev/cu.*
→ pppd
```

不需要实现完整 QMI，只要实现 USB 串口桥接即可。

## 10. 后续研究方向

1. 完成 Windows MI_03 PPP/RAS 拨号
2. 完成 macOS USBSerialDriverKit 最小驱动
3. 查找或提取 Fibocom NL668 Windows 完整驱动包
4. 研究 Qualcomm GobiNet/Fibocom Linux 专用驱动
5. 抓取 DJI 遥控器/飞行器使用模块时的 USB 控制流量
6. 分析 GTUSBMODE 30 的真实接口定义
7. 确认 MI_01 和 MI_04 的准确用途
8. 整理成 GitHub 项目，附 USB descriptor、INF 映射和系统适配说明

## 11. 安全提示

不要随意执行：

```text
AT+GTUSBMODE=<未知值>
刷写未知固件
修改 IMEI
删除或覆盖运营商配置
对 MI_04 发送未知二进制协议
```

建议保留：

- 当前固件版本

- 当前 `GTUSBMODE=30`

- 原始 USB descriptor

- Windows INF 备份

- Linux dmesg 与接口映射

- AT 查询结果

  ​                                                                                                                                                                                                         YUNFENG2232
