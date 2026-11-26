# 备份与恢复说明（TB323FU / YOUR_SERIAL）

> 配套脚本：`backup_partitions.sh`（dd 全量备份，adb exec-out 方式，不落 /sdcard）
> 数据基准：`05_备份索引/` 2026-11-22 实测存档（by-name 141 项 + getvar 280 项）
> 适用范围：仅供本机 YOUR_SERIAL（ZUXOS 2.0.12.043_ST，SM8850P 12+256）使用。
> **禁止将本机备份刷入他人设备；禁止回锁、禁止写他人字库。**

## 一、备份用法

```bash
# 先跑干跑，确认清单与命令无误（不需要连接设备）
./backup_partitions.sh --dry-run

# 常规备份（15 个必做分区，当前槽位 b + 无槽位分区）
./backup_partitions.sh

# 完整备份（追加 super 约 20GB、devcfg_a、modem_a、init_boot_a）
./backup_partitions.sh --full --out D:/Y700_备份/20261122
```

前置条件（脚本会自动检查，不过人工也要知道）：
1. 设备已解锁 Bootloader 并已 root（`adb shell su -c id` 返回 uid=0）
2. USB 用侧边中置口直连电脑（fastboot/adb 通道坑见 `00_救生包/救砖SOP.md`）
3. 电脑 adb 在 PATH 中，且只有一个设备在线

执行后每个分区依次做三项校验：
1. 实际文件大小 == getvar 存档 partition-size（十六进制精确比对）
2. SHA256 计算并写入 CSV
3. 试读前 1KB，确认非全零（防 dd 读空节点）

产出：`backup_YYYYMMDD_HHMMSS/备份项.img` + `backup_log.csv`（表头与 `05_备份索引/备份登记表.md` 对齐：备份项,文件路径,大小,SHA256,试读验证,电脑位置,云盘位置,日期）。完成后誊入登记表，并做电脑+云盘双备份后才允许进入刷写。

## 二、恢复命令对照表

> 恢复是高危操作：执行前逐字核对分区名与文件，用户人工复核后执行（分工说明·证据与安全规范 1）。
> 恢复时设备须在 fastboot 模式（`adb reboot bootloader`）。
> 注意：当前运行槽位为 **b**（a 槽 slot_a 标记 unbootable，可能无完整系统）。

### 2.1 fastboot 直刷分区（bootloader 模式下）

| 备份项 | 恢复命令 | 说明 |
|---|---|---|
| boot_b | `fastboot flash boot_b boot_b.img` | 内核+rootfs 头 |
| init_boot_b | `fastboot flash init_boot_b init_boot_b.img` | 原厂 init_boot，Magisk 修补对象 |
| vendor_boot_b | `fastboot flash vendor_boot_b vendor_boot_b.img` | vendor ramdisk |
| dtbo_b | `fastboot flash dtbo_b dtbo_b.img` | 设备树叠加 |
| vbmeta_b | `fastboot flash vbmeta_b vbmeta_b.img` | 关闭校验时需 --disable-verity 另行裁定 |
| vbmeta_system_b | `fastboot flash vbmeta_system_b vbmeta_system_b.img` | 同上 |
| devcfg_b | `fastboot flash devcfg_b devcfg_b.img` | 设备配置 |
| modem_b | `fastboot flash modem_b modem_b.img` | 基带固件（WiFi 版仍含 modem 分区） |
| devcfg_a | `fastboot flash devcfg_a devcfg_a.img` | --full 才备份 |
| modem_a | `fastboot flash modem_a modem_a.img` | --full 才备份 |
| init_boot_a | `fastboot flash init_boot_a init_boot_a.img` | --full 才备份 |

### 2.2 fastbootd 刷写（super 必须走 fastbootd，不能停留 bootloader）

```bash
adb reboot fastboot          # 进入 fastbootd（用户空间 fastboot，界面显示 FASTBOOTD）
fastboot flash super super.img
```
super 约 20GB，刷写耗时长，过程中严禁断线断电。

### 2.3 无 fastboot 对应名的分区（raw 节点，dd 写回）

以下分区 getvar 中无独立分区名或 fastboot 不支持直刷，救砖时只能在 **root 后的系统** 或 recovery 里 dd 写回（高危，需总管另行派单，不在本 README 授权执行）：

| 备份项 | 设备节点 | 用途 |
|---|---|---|
| persist | /dev/block/sda3 | WiFi/蓝牙/传感器校准，丢失会硬件功能异常 |
| metadata | /dev/block/sda10 | 加密元数据 |
| oemowninfo | /dev/block/sda1 | OEM 信息 |
| modemst1 | /dev/block/sdf2 | 基带 NV（EFS） |
| modemst2 | /dev/block/sdf3 | 基带 NV 备份 |
| fsg | /dev/block/sdf4 | 基带 Golden 副本 |
| fsc | /dev/block/sdf5 | 基带状态 |

## 三、回退原则

- 任何时候刷写失败：用 2.1 表逐分区刷回 b 槽镜像，再 `fastboot reboot`。
- bootloader 损坏（fastboot 都进不去）：走 `00_救生包/救砖SOP.md` 的 9008 通道（另线负责）。
- 备份文件严禁改名混放，SHA256 以登记表为准。
