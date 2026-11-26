package com.y700.icharger;

import android.os.Binder;
import android.os.IBinder;
import android.os.Looper;
import android.os.Parcel;
import android.os.Process;
import android.os.RemoteException;

import java.io.File;
import java.io.FileOutputStream;
import java.io.RandomAccessFile;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;

/**
 * y700_icharger —— 补上 ColorOS 需要但本机缺失的 vendor.oplus.hardware.charger.ICharger。
 * 只回真实值：语义已核实的两个方法按内核 charge_type 如实回答；其余一律回"不支持"异常，
 * 与本机今天（服务缺失）对框架的行为一致，同时把每次调用记进日志用于后续取证。
 * 不做的事：不把 PD/QC 谎报成 VOOC/超级快充，不实现任何会改硬件状态的 set* 方法。
 */
public class Main {
    static final String DESCRIPTOR = "vendor.oplus.hardware.charger.ICharger";
    static final String SERVICE_NAME = DESCRIPTOR + "/default";
    static final int INTERFACE_VERSION = 12;
    static final String INTERFACE_HASH = "fe84d18cb5595f64620e559af7f86413aa09a095";
    static final String LOG_PATH = "/data/local/tmp/y700_icharger_calls.log";
    static final String NODE_CHARGE_TYPE = "/sys/class/power_supply/battery/charge_type";

    /** 一次性取证开关（用户 14:1x 授权"试探后即撤"）：给未证实语义的 get* 回 9000+码，用于反推哪个供了 settings 键。验完必须置回 false。 */
    static final boolean PROBE = false;

    // AIDL 保留码
    static final int CODE_GET_INTERFACE_VERSION = 0x00ffffff;
    static final int CODE_GET_INTERFACE_HASH = 0x00fffffe;

    static final HashMap<Integer, String> NAMES = new HashMap<>();
    static {
@@NAME_MAP@@
    }

    public static void main(String[] argv) throws Exception {
        Class<?> sm = Class.forName("android.os.ServiceManager");
        Object old = sm.getMethod("checkService", String.class).invoke(null, SERVICE_NAME);
        if (old != null) {
            log("FATAL 服务名已被占用，拒绝接管：" + SERVICE_NAME);
            return;
        }
        sm.getMethod("addService", String.class, IBinder.class).invoke(null, SERVICE_NAME, new Charger());
        Object back = sm.getMethod("checkService", String.class).invoke(null, SERVICE_NAME);
        log("started pid=" + Process.myPid() + " 注册后回读 " + SERVICE_NAME + " -> " + back);
        Looper.prepareMainLooper();
        Looper.loop();
    }

    static class Charger extends Binder {
        @Override
        protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
            if (code == CODE_GET_INTERFACE_VERSION) {
                if (reply != null) {
                    reply.writeNoException();
                    reply.writeInt(INTERFACE_VERSION);
                }
                return true;
            }
            if (code == CODE_GET_INTERFACE_HASH) {
                if (reply != null) {
                    reply.writeNoException();
                    reply.writeString(INTERFACE_HASH);
                }
                return true;
            }
            data.enforceInterface(DESCRIPTOR);

            Object[] args = null;
            String[] shown = null;
            switch (code) {
@@READ_CASES@@
                default:
                    shown = new String[]{"<未知码>"};
                    args = new Object[0];
            }

            String name = NAMES.get(code);
            if (name == null) {
                name = "code" + code;
            }

            // 已核实语义、可如实回答的方法
            switch (code) {
                case 24: { // getFastCharge -> int，真实：内核 charge_type 是否 Fast
                    int v = isFast() ? 1 : 0;
                    done(code, name, shown, String.valueOf(v));
                    if (reply != null) {
                        reply.writeNoException();
                        reply.writeInt(v);
                    }
                    return true;
                }
                case 40: { // getPsyChargeTech -> int，真实：快充=FAST_CHARGER_TECHNOLOGY(1)，非快充=NORMAL(0)
                    int v = isFast() ? 1 : 0;
                    done(code, name, shown, String.valueOf(v));
                    if (reply != null) {
                        reply.writeNoException();
                        reply.writeInt(v);
                    }
                    return true;
                }
                case 128: { // getChgConfig(funcId, "", arg) -> String
                    int func = -1;
                    try {
                        func = Integer.parseInt(shown != null && shown.length > 0 ? shown[0] : "");
                    } catch (Throwable ignored) {
                    }
                    String v = null;
                    if (func == 0) {
                        // 框架把该值 parseInt 后写进 mChargerTechnology（0=NORMAL，1=FAST，2=VOOC）
                        v = String.valueOf(isFast() ? 1 : 0);
                    } else if (func == 1) {
                        // 框架把该值 parseInt 后写进 mChargeWattage
                        v = String.valueOf(wattageW());
                    } else if (PROBE) {
                        v = String.valueOf(9000 + func);
                    }
                    if (v != null) {
                        done(code, name, shown, v);
                        if (reply != null) {
                            reply.writeNoException();
                            reply.writeString(v);
                        }
                        return true;
                    }
                    break;
                }
                default:
                    break;
            }

            if (PROBE && name.startsWith("get") && code != 24 && code != 40 && code != 128) {
                int v = 9000 + code;
                done(code, name, shown, "PROBE " + v);
                if (reply != null) {
                    reply.writeNoException();
                    reply.writeInt(v);
                }
                return true;
            }

            // getChargerControl() -> String：调用方 com.oplus.onetrace 在电池广播里直接调它且不接异常，
            // 抛 UnsupportedOperationException 会让它每轮崩 10 个进程（11-25 20:4x 日志扫描实测）。
            // 回 null 与"服务不存在"时框架拿到的值相同，属如实无数据，不伪造读数。
            if (code == 17) {
                done(code, name, shown, "null(无数据)");
                if (reply != null) {
                    reply.writeNoException();
                    reply.writeString(null);
                }
                return true;
            }

            // 其余：如实告知不支持（框架原本就走异常分支，行为不变），并留下调用证据
            done(code, name, shown, "UNSUPPORTED");
            if (reply != null) {
                reply.writeException(new UnsupportedOperationException("y700_icharger: " + name + " 未实现"));
            }
            return true;
        }
    }

    static void done(int code, String name, String[] args, String result) {
        log("tid=" + Process.myTid() + " caller=" + Binder.getCallingPid() + "/" + Binder.getCallingUid()
                + " #" + code + " " + name + "(" + join(args) + ") -> " + result);
    }

    static String join(String[] a) {
        if (a == null) {
            return "?";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < a.length; i++) {
            if (i > 0) {
                sb.append(',');
            }
            sb.append(a[i]);
        }
        return sb.toString();
    }

    static boolean isFast() {
        String s = readNode(NODE_CHARGE_TYPE);
        return s != null && "Fast".equals(s.trim());
    }

    /** 适配器此刻报出的输入上限（µV × µA）换算成瓦；取不到就回 0，不猜。 */
    static int wattageW() {
        long uv = nodeLong("/sys/class/power_supply/usb/voltage_max");
        long ua = nodeLong("/sys/class/power_supply/usb/current_max");
        if (uv > 0 && ua > 0) {
            return (int) ((uv * ua) / 1000000000000L);
        }
        return 0;
    }

    static long nodeLong(String path) {
        String s = readNode(path);
        if (s == null) {
            return -1;
        }
        try {
            return Long.parseLong(s.trim());
        } catch (Throwable t) {
            return -1;
        }
    }

    static String readNode(String path) {
        java.io.InputStream in = null;
        try {
            in = new java.io.FileInputStream(path);
            byte[] buf = new byte[128];
            int n = in.read(buf);
            return n <= 0 ? null : new String(buf, 0, n);
        } catch (Throwable t) {
            return null;
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }

    // 日志封顶写在进程内：service.sh 里那个外部巡查循环实测起不来（11-25 重启后设备侧只剩 jar 进程，
    // 日志 4 小时涨到 8.67MB），外部兜底不可依赖。
    static final long LOG_MAX = 1048576;
    static final int LOG_KEEP = 262144;
    static long logBytes = -1;
    static long logSinceCheck = 0;

    static synchronized void log(String s) {
        try {
            File f = new File(LOG_PATH);
            if (logBytes < 0) {
                logBytes = f.length();
            }
            byte[] line = (new SimpleDateFormat("MM-dd HH:mm:ss").format(new Date()) + " " + s + "\n").getBytes();
            FileOutputStream o = new FileOutputStream(f, true);
            o.write(line);
            o.close();
            logBytes += line.length;
            logSinceCheck += line.length;
            if (logSinceCheck < 65536 || logBytes <= LOG_MAX) {
                return;
            }
            logSinceCheck = 0;
            RandomAccessFile raf = new RandomAccessFile(f, "rw");
            try {
                long len = raf.length();
                if (len > LOG_KEEP) {
                    byte[] buf = new byte[LOG_KEEP];
                    raf.seek(len - LOG_KEEP);
                    raf.readFully(buf);
                    raf.seek(0);
                    raf.write(buf);
                    raf.setLength(LOG_KEEP);
                    logBytes = LOG_KEEP;
                } else {
                    logBytes = len;
                }
            } finally {
                raf.close();
            }
        } catch (Throwable ignored) {
            logBytes = -1;
            logSinceCheck = 0;
        }
    }
}
