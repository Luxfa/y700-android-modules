# 和平营地「画面提升」开关 A/B 取证归档（2026-11-25 19:4x~20:1x）

结论正文：`操作流水账.md` §一百零一（五轮 A/B 定档）与 §一百零二（机制底：`r.MobileContentScaleFactor 1.0→1.5` + 砍后处理）。

| 件 | 内容 |
|---|---|
| `ab_OFF1.txt` / `ab_Q1.txt` / `ab_QF1.txt` / `ab_ON3.txt` / `ab_ALL1.txt` | 五轮 12 段指纹（渲染层、显示档、10 秒层帧计数、游戏与营地文件指纹、属性、负载、温度）；状态由用户当场告知：全关 / 只开画质 / 画质+分辨率 / 画质+分辨率+功耗自适应 / 同第四次（重复） |
| `UserCustom_ON.ini` / `UserCustom_OFF.ini` | UE4 配置原文（值＝逐字节 hex + 单字节异或 **0x79**） |
| `UserCustom_ON_dec.txt` | 开态解码后的 292 条 CVar 全文 |
| `playerprefs_ON.sav` / `playerprefs_OFF.sav` | UE4 PlayerPrefs 原件；差异＝`art_quality_improve` 键后单字节 `01`↔`00` |

复现解码：`python -c "print(''.join(chr(c^0x79) for c in bytes.fromhex(open('UserCustom_ON.ini').read().split('+CVars=')[1][:64])))"`
采样工具：`03_脚本与模块/自检取证/游戏画质探针.sh`
