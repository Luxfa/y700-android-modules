# 作业指导书：解锁 → Root → dd 全量备份（主线执行用）

> 用途：sn.img 与线刷包到手后的主线操作序列。总管（AI）逐条生成命令，用户在关键复核点确认。
> 铁律：未经版本对齐（0.3.5）不得解锁；未完成 dd 全量备份不得刷 ColorOS。

## 前置检查（执行当天逐项确认）

- [ ] sn.img 已存 `00_救生包/`，来源为联想官方邮件
- [ ] 线刷包已验包通过（含 firehose+rawprogram，SHA256 已登记）
- [ ] 设备版本已对齐到线刷包版本（`adb shell getprop ro.build.display.id` 与包版本一致）
- [ ] 平板电量 >60%，插**侧边中置**USB口
- [ ] 本日《操作流水账》已开新行

## 0.6 解锁 BL

```bash
adb reboot bootloader                      # 进 fastboot（屏幕显示 FastBoot Mode）
fastboot devices                           # 确认识别
fastboot getvar all > "05_备份索引/fastboot_getvar_all_解锁前_$(date +%Y%m%d).txt" 2>&1
# 解锁命令（社区实证序列，sn.img 在 adb 同目录）：
fastboot flash unlock sn.img
fastboot oem unlock-go
# 【设备动作】平板屏幕出现 UNLOCK 提示时，长按开机键确认一次
fastboot devices                           # 复核：应显示 device unlocked
```
- wipe 后首次开机：跳过全部账号登录，**第一件事开 USB 调试**（设置-关于-版本号连点；开发者选项开 USB 调试 + OEM 解锁开关复查）
- `adb devices` 重新授权

## 0.7 Root

```bash
# 从线刷包提取同版 init_boot.img（对应槽位 b），推到设备
adb push init_boot.img /sdcard/Download/
# 安装 Magisk（00_救生包/tools/Magisk-v31.1.apk）
adb install "00_救生包/tools/Magisk-v31.1.apk"
# 【设备上手动】Magisk → 安装 → 选择并修补一个文件 → 选 init_boot.img → 产出 magisk_patched-*.img
adb pull /sdcard/Download/magisk_patched-*.img ./
adb reboot bootloader
fastboot flash init_boot_b magisk_patched-*.img   # 【只刷 b 槽！a 槽已废】
fastboot reboot
# 回系统后验证：
adb shell su -c id                                # Magisk 弹窗授权后应返回 uid=0
```

## 0.8 dd 全量备份

```bash
cd 03_脚本与模块
./backup_partitions.sh --dry-run                  # 先干跑核对清单
./backup_partitions.sh --full --out "D:/Y700备份/$(date +%Y%m%d)"
```
- 检查 backup_log.csv：无"失败"行
- 誊入 `05_备份索引/备份登记表.md`
- **云盘双备份**完成后，阶段0 收官，才允许进入阶段1 刷 ColorOS

## 应急

| 情况 | 处置 |
|---|---|
| 解锁命令报错 | 停手，截图报文给总管，核对 sn.img 与命令格式 |
| 刷 init_boot 后 bootloop | `fastboot flash init_boot_b init_boot.img`（用包内提取的原版刷回）→ `fastboot reboot` |
| fastboot 认不到 | 检查是否插的侧边口；设备管理器 Android 叹号则按 SOP 重绑驱动 |
| 任何命令输出与预期不符 | 停手记录流水账，找总管，不自由发挥 |
