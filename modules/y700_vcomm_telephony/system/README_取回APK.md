# Telecom.apk / ims.apk 不入 git 的说明

这两个 APK 体积 18MB，且**权威来源就是平板自身**，随时可重新拉取，不必进版本库：

    A=/d/y700work/bin/adb.exe; P=192.0.2.10:5555
    $A -s $P shell "/debug_ramdisk/su -c 'cp /system_ext/priv-app/Telecom/Telecom.apk /system_ext/priv-app/ims/ims.apk /data/local/tmp/; chmod 644 /data/local/tmp/*.apk'"
    $A -s $P pull /data/local/tmp/Telecom.apk D:/y700work/vcomm_mod/system/system_ext/priv-app/Telecom/Telecom.apk
    $A -s $P pull /data/local/tmp/ims.apk     D:/y700work/vcomm_mod/system/system_ext/priv-app/ims/ims.apk

装机时校验用（相位Z 记录的值，用于确认没拿错版本）：

- Telecom.apk  16,939,847 B  sha256 `c9e2465e8b4570dee16a9811dc2e98f2c0294e0a58a5ecdefcf1538beff59c5e`
- ims.apk       1,021,414 B  sha256 `93c199d707cd6dd908b82e3d24d7aa3bdc15f28aa858aae9b9b14c362ca1f48c`

本模块缺这两个 APK 就不能工作（Android 16 起 Telecom 与 IMS 已 priv-app 化，移植包把它们整个砍掉了），
所以重装模块前必须先按上面的命令补齐，再推送。

---

## 11-24 审计更正与加固（相位G1）

**上文"权威来源就是平板自身"这个说法有循环依赖**：平板 `/system_ext/priv-app/Telecom/Telecom.apk` 之所以存在，
是 Magisk 把本模块 `system/` 下的副本挂上去的（`mount` 实测：`magisk on /system_ext/priv-app type tmpfs`）。
设备若变砖，按上面的命令无从拉取 ⇒ **回退链单点**。

**真实离线来源已查明**：供体 `06_二期自制移植/解包区/OPD2513_17.0.0.105/system_ext.img` 内有原件 `/priv-app/Telecom/Telecom.apk`。
但我方 EROFS 工具解不出这两个大文件（`ValueError: pcluster 解码异常 nid=27684224 blk=[213996,214010)`），
`erofs_read.py` 的多 pcluster 路径对 17MB 级文件仍不可靠 ⇒ 供体侧抽取留作后续工程项。

**已落地的加固（本次）**：把设备上**正在使用**的这两件 APK 拉回仓库常驻：

    05_备份索引/vcomm_apk_inuse/Telecom.apk  16,939,847 B  sha256 c9e2465e8b4570dee16a9811dc2e98f2c0294e0a58a5ecdefcf1538beff59c5e
    05_备份索引/vcomm_apk_inuse/ims.apk       1,021,414 B  sha256 93c199d707cd6dd908b82e3d24d7aa3bdc15f28aa858aae9b9b14c362ca1f48c

两个 sha256 与本文上方 相位Z 记录值**逐字节相同** ⇒ 在用副本与历史记录同一件，无漂移。
今后重装模块直接从 `05_备份索引/vcomm_apk_inuse/` 拷回，不再依赖设备在线。
