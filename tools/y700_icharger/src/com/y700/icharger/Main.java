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
        NAMES.put(1, "VolDividerIcWorkModeSet");
        NAMES.put(2, "chgExchangeMesgInit");
        NAMES.put(3, "chgExchangeSohMesgInit");
        NAMES.put(4, "getAcType");
        NAMES.put(5, "getBattAuthenticate");
        NAMES.put(6, "getBattPPSChgIng");
        NAMES.put(7, "getBattPPSChgPower");
        NAMES.put(8, "getBattParamNoplug");
        NAMES.put(9, "getBattShortIcOtpStatus");
        NAMES.put(10, "getBattSubCurrent");
        NAMES.put(11, "getBattVoocChgIng");
        NAMES.put(12, "getBatteryVoltageNow");
        NAMES.put(13, "getBccCsvData");
        NAMES.put(14, "getBccExpStatus");
        NAMES.put(15, "getBmsHeatingRunningStatus");
        NAMES.put(16, "getBmsHeatingStatus");
        NAMES.put(17, "getChargerControl");
        NAMES.put(18, "getChargerCoolDown");
        NAMES.put(19, "getChargerCriticalLog");
        NAMES.put(20, "getChargerIdVolt");
        NAMES.put(21, "getChargerLog");
        NAMES.put(22, "getCustomSelectChgMode");
        NAMES.put(23, "getDevinfoFastchg");
        NAMES.put(24, "getFastCharge");
        NAMES.put(25, "getParallelChgMosTestResult");
        NAMES.put(26, "getPsyAcOnline");
        NAMES.put(27, "getPsyBatteryCC");
        NAMES.put(28, "getPsyBatteryCurrentNow");
        NAMES.put(29, "getPsyBatteryFcc");
        NAMES.put(30, "getPsyBatteryHmac");
        NAMES.put(31, "getPsyBatteryLevel");
        NAMES.put(32, "getPsyBatteryNotify");
        NAMES.put(33, "getPsyBatteryPchg");
        NAMES.put(34, "getPsyBatteryPchgResetCount");
        NAMES.put(35, "getPsyBatteryRm");
        NAMES.put(36, "getPsyBatteryShortFeature");
        NAMES.put(37, "getPsyBatteryShortStatus");
        NAMES.put(38, "getPsyBatteryStatus");
        NAMES.put(39, "getPsyBatteryTemp");
        NAMES.put(40, "getPsyChargeTech");
        NAMES.put(41, "getPsyFastChgType");
        NAMES.put(42, "getPsyInputCurrent");
        NAMES.put(43, "getPsyOtgOnline");
        NAMES.put(44, "getPsyOtgSwitch");
        NAMES.put(45, "getPsyPcPortOnline");
        NAMES.put(46, "getPsyQGVbatDeviation");
        NAMES.put(47, "getPsyTypeOrientation");
        NAMES.put(48, "getPsyUsbOnline");
        NAMES.put(49, "getPsyUsbStatus");
        NAMES.put(50, "getPsyWirelessRX");
        NAMES.put(51, "getPsyWirelessRxVersion");
        NAMES.put(52, "getPsyWirelessTX");
        NAMES.put(53, "getPsyWirelessTxVersion");
        NAMES.put(54, "getQgVbatDeviation");
        NAMES.put(55, "getQuickModeGain");
        NAMES.put(56, "getReserveSocDebug");
        NAMES.put(57, "getSmartChgMode");
        NAMES.put(58, "getUIsohValue");
        NAMES.put(59, "getUisohDebugParameterInfo");
        NAMES.put(60, "getUsbInputCurrentNow");
        NAMES.put(61, "getUsbPrimalType");
        NAMES.put(62, "getWiredOtgOnline");
        NAMES.put(63, "getWirelessAdapterPower");
        NAMES.put(64, "getWirelessCapacity");
        NAMES.put(65, "getWirelessChargePumpEn");
        NAMES.put(66, "getWirelessCurrentNow");
        NAMES.put(67, "getWirelessDeviated");
        NAMES.put(68, "getWirelessOnline");
        NAMES.put(69, "getWirelessPenPresent");
        NAMES.put(70, "getWirelessPtmcId");
        NAMES.put(71, "getWirelessRXEnable");
        NAMES.put(72, "getWirelessRealType");
        NAMES.put(73, "getWirelessTXEnable");
        NAMES.put(74, "getWirelessUserSleepMode");
        NAMES.put(75, "getWirelessVoltageNow");
        NAMES.put(76, "healthd_update_ui_soc_decimal");
        NAMES.put(77, "nightstandby");
        NAMES.put(78, "notifyScreenStatus");
        NAMES.put(79, "queryChargeInfo");
        NAMES.put(80, "setChargeEMMode");
        NAMES.put(81, "setChargerControl");
        NAMES.put(82, "setChargerCoolDown");
        NAMES.put(83, "setChargerCriticalLog");
        NAMES.put(84, "setChargerCycle");
        NAMES.put(85, "setChargerFactoryModeTest");
        NAMES.put(86, "setChargerLog");
        NAMES.put(87, "setChgStatusToBcc");
        NAMES.put(88, "setCustomSelectChgMode");
        NAMES.put(89, "setFastchgFwUpdate");
        NAMES.put(90, "setPsyMmiChgEn");
        NAMES.put(91, "setPsyOtgSwitch");
        NAMES.put(92, "setReserveSocDebug");
        NAMES.put(93, "setShipMode");
        NAMES.put(94, "setSmartChgMode");
        NAMES.put(95, "setSmartCoolDown");
        NAMES.put(96, "setTbattPwrOff");
        NAMES.put(97, "setUisohDebugInfo");
        NAMES.put(98, "setUsbPrimalType");
        NAMES.put(99, "setWirelessChargePumpEn");
        NAMES.put(100, "setWirelessFtmMode");
        NAMES.put(101, "setWirelessIconDelay");
        NAMES.put(102, "setWirelessIdtAdcTest");
        NAMES.put(103, "setWirelessPenSoc");
        NAMES.put(104, "setWirelessRXEnable");
        NAMES.put(105, "setWirelessTXEnable");
        NAMES.put(106, "setWirelessUserSleepMode");
        NAMES.put(107, "setWlsThirdPartitionInfo");
        NAMES.put(108, "testKitFeatureTest");
        NAMES.put(109, "testKitGetFeatureList");
        NAMES.put(110, "testKitGetFeatureName");
        NAMES.put(111, "testKitGetFeatureNum");
        NAMES.put(112, "updateUiSohToPartion");
        NAMES.put(113, "queryWlsPencilInfo");
        NAMES.put(114, "getChgOlcConfig");
        NAMES.put(115, "setChgOlcConfig");
        NAMES.put(116, "setSuperEnduranceStatus");
        NAMES.put(117, "setSuperEnduranceCount");
        NAMES.put(118, "setBobStatus");
        NAMES.put(119, "setPsySlowChgEn");
        NAMES.put(120, "getCpVbatDeviation");
        NAMES.put(121, "setBatteryLogPush");
        NAMES.put(122, "getChargingModeInGsmCall");
        NAMES.put(123, "setChargingModeInGsmCall");
        NAMES.put(124, "setChgRusConfig");
        NAMES.put(125, "getPsyBatterySN");
        NAMES.put(126, "getBattGaugeInfo");
        NAMES.put(127, "setChgConfig");
        NAMES.put(128, "getChgConfig");
        NAMES.put(129, "setUsbEyeDiagram");
        NAMES.put(130, "getUsbCurrentEyeDiagram");
        NAMES.put(131, "queryRgcpHboostInfo");
        NAMES.put(132, "setCV");
        NAMES.put(133, "getDeepSleepClustersSleepWake");
        NAMES.put(134, "getPowerbankInfo");
        NAMES.put(16777214, "getInterfaceHash");
        NAMES.put(16777215, "getInterfaceVersion");
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
        case 1: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 2: args = new Object[0]; shown = new String[0]; break;
        case 3: args = new Object[0]; shown = new String[0]; break;
        case 4: args = new Object[0]; shown = new String[0]; break;
        case 5: args = new Object[0]; shown = new String[0]; break;
        case 6: args = new Object[0]; shown = new String[0]; break;
        case 7: args = new Object[0]; shown = new String[0]; break;
        case 8: args = new Object[0]; shown = new String[0]; break;
        case 9: args = new Object[0]; shown = new String[0]; break;
        case 10: args = new Object[0]; shown = new String[0]; break;
        case 11: args = new Object[0]; shown = new String[0]; break;
        case 12: args = new Object[0]; shown = new String[0]; break;
        case 13: args = new Object[0]; shown = new String[0]; break;
        case 14: args = new Object[0]; shown = new String[0]; break;
        case 15: args = new Object[0]; shown = new String[0]; break;
        case 16: args = new Object[0]; shown = new String[0]; break;
        case 17: args = new Object[0]; shown = new String[0]; break;
        case 18: args = new Object[0]; shown = new String[0]; break;
        case 19: args = new Object[0]; shown = new String[0]; break;
        case 20: args = new Object[0]; shown = new String[0]; break;
        case 21: args = new Object[0]; shown = new String[0]; break;
        case 22: args = new Object[0]; shown = new String[0]; break;
        case 23: args = new Object[0]; shown = new String[0]; break;
        case 24: args = new Object[0]; shown = new String[0]; break;
        case 25: args = new Object[0]; shown = new String[0]; break;
        case 26: args = new Object[0]; shown = new String[0]; break;
        case 27: args = new Object[0]; shown = new String[0]; break;
        case 28: args = new Object[0]; shown = new String[0]; break;
        case 29: args = new Object[0]; shown = new String[0]; break;
        case 30: args = new Object[0]; shown = new String[0]; break;
        case 31: args = new Object[0]; shown = new String[0]; break;
        case 32: args = new Object[0]; shown = new String[0]; break;
        case 33: args = new Object[0]; shown = new String[0]; break;
        case 34: args = new Object[0]; shown = new String[0]; break;
        case 35: args = new Object[0]; shown = new String[0]; break;
        case 36: args = new Object[0]; shown = new String[0]; break;
        case 37: args = new Object[0]; shown = new String[0]; break;
        case 38: args = new Object[0]; shown = new String[0]; break;
        case 39: args = new Object[0]; shown = new String[0]; break;
        case 40: args = new Object[0]; shown = new String[0]; break;
        case 41: args = new Object[0]; shown = new String[0]; break;
        case 42: args = new Object[0]; shown = new String[0]; break;
        case 43: args = new Object[0]; shown = new String[0]; break;
        case 44: args = new Object[0]; shown = new String[0]; break;
        case 45: args = new Object[0]; shown = new String[0]; break;
        case 46: args = new Object[0]; shown = new String[0]; break;
        case 47: args = new Object[0]; shown = new String[0]; break;
        case 48: args = new Object[0]; shown = new String[0]; break;
        case 49: args = new Object[0]; shown = new String[0]; break;
        case 50: args = new Object[0]; shown = new String[0]; break;
        case 51: args = new Object[0]; shown = new String[0]; break;
        case 52: args = new Object[0]; shown = new String[0]; break;
        case 53: args = new Object[0]; shown = new String[0]; break;
        case 54: args = new Object[0]; shown = new String[0]; break;
        case 55: args = new Object[0]; shown = new String[0]; break;
        case 56: args = new Object[0]; shown = new String[0]; break;
        case 57: args = new Object[0]; shown = new String[0]; break;
        case 58: args = new Object[0]; shown = new String[0]; break;
        case 59: args = new Object[0]; shown = new String[0]; break;
        case 60: args = new Object[0]; shown = new String[0]; break;
        case 61: args = new Object[0]; shown = new String[0]; break;
        case 62: args = new Object[0]; shown = new String[0]; break;
        case 63: args = new Object[0]; shown = new String[0]; break;
        case 64: args = new Object[0]; shown = new String[0]; break;
        case 65: args = new Object[0]; shown = new String[0]; break;
        case 66: args = new Object[0]; shown = new String[0]; break;
        case 67: args = new Object[0]; shown = new String[0]; break;
        case 68: args = new Object[0]; shown = new String[0]; break;
        case 69: args = new Object[0]; shown = new String[0]; break;
        case 70: args = new Object[0]; shown = new String[0]; break;
        case 71: args = new Object[0]; shown = new String[0]; break;
        case 72: args = new Object[0]; shown = new String[0]; break;
        case 73: args = new Object[0]; shown = new String[0]; break;
        case 74: args = new Object[0]; shown = new String[0]; break;
        case 75: args = new Object[0]; shown = new String[0]; break;
        case 76: args = new Object[0]; shown = new String[0]; break;
        case 77: {
            int v0 = data.readInt();
            args = new Object[]{ v0 };
            shown = new String[]{ String.valueOf(v0) };
        } break;
        case 78: {
            int v0 = data.readInt();
            args = new Object[]{ v0 };
            shown = new String[]{ String.valueOf(v0) };
        } break;
        case 79: args = new Object[0]; shown = new String[0]; break;
        case 80: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 81: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 82: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 83: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 84: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 85: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 86: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 87: {
            int v0 = data.readInt();
            args = new Object[]{ v0 };
            shown = new String[]{ String.valueOf(v0) };
        } break;
        case 88: {
            int v0 = data.readInt();
            int v1 = data.readInt();
            args = new Object[]{ v0, v1 };
            shown = new String[]{ String.valueOf(v0), String.valueOf(v1 != 0) };
        } break;
        case 89: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 90: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 91: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 92: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 93: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 94: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 95: {
            int v0 = data.readInt();
            int v1 = data.readInt();
            String v2 = data.readString();
            args = new Object[]{ v0, v1, v2 };
            shown = new String[]{ String.valueOf(v0), String.valueOf(v1), v2 };
        } break;
        case 96: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 97: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 98: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 99: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 100: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 101: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 102: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 103: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 104: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 105: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 106: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 107: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 108: {
            int v0 = data.readInt();
            args = new Object[]{ v0 };
            shown = new String[]{ String.valueOf(v0) };
        } break;
        case 109: args = new Object[0]; shown = new String[0]; break;
        case 110: {
            int v0 = data.readInt();
            args = new Object[]{ v0 };
            shown = new String[]{ String.valueOf(v0) };
        } break;
        case 111: args = new Object[0]; shown = new String[0]; break;
        case 112: args = new Object[0]; shown = new String[0]; break;
        case 113: args = new Object[0]; shown = new String[0]; break;
        case 114: args = new Object[0]; shown = new String[0]; break;
        case 115: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 116: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 117: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 118: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 119: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 120: args = new Object[0]; shown = new String[0]; break;
        case 121: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 122: args = new Object[0]; shown = new String[0]; break;
        case 123: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 124: {
            String v0 = data.readString();
            args = new Object[]{ v0 };
            shown = new String[]{ v0 };
        } break;
        case 125: args = new Object[0]; shown = new String[0]; break;
        case 126: args = new Object[0]; shown = new String[0]; break;
        case 127: {
            int v0 = data.readInt();
            String v1 = data.readString();
            int v2 = data.readInt();
            args = new Object[]{ v0, v1, v2 };
            shown = new String[]{ String.valueOf(v0), v1, String.valueOf(v2) };
        } break;
        case 128: {
            int v0 = data.readInt();
            String v1 = data.readString();
            int v2 = data.readInt();
            args = new Object[]{ v0, v1, v2 };
            shown = new String[]{ String.valueOf(v0), v1, String.valueOf(v2) };
        } break;
        case 129: {
            int v0 = data.readInt();
            String v1 = data.readString();
            int v2 = data.readInt();
            args = new Object[]{ v0, v1, v2 };
            shown = new String[]{ String.valueOf(v0), v1, String.valueOf(v2 != 0) };
        } break;
        case 130: {
            int v0 = data.readInt();
            args = new Object[]{ v0 };
            shown = new String[]{ String.valueOf(v0) };
        } break;
        case 131: args = new Object[0]; shown = new String[0]; break;
        case 132: {
            int v0 = data.readInt();
            int v1 = data.readInt();
            args = new Object[]{ v0, v1 };
            shown = new String[]{ String.valueOf(v0), String.valueOf(v1) };
        } break;
        case 133: args = new Object[0]; shown = new String[0]; break;
        case 134: {
            String v0 = data.readString();
            int v1 = data.readInt();
            args = new Object[]{ v0, v1 };
            shown = new String[]{ v0, String.valueOf(v1) };
        } break;
        case 16777214: args = new Object[0]; shown = new String[0]; break;
        case 16777215: args = new Object[0]; shown = new String[0]; break;
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
