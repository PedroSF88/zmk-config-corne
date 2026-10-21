// Keyboard input for the Corne overlay (loaded by Start-LayerOverlay.ps1).
//
// CorneHook      low-level keyboard hook. Catches the F13-F16 layer signals the
//                keymap's to_layerN macros send and swallows them, so no app
//                sees them. With AllKeys set it also reports every other key
//                from every keyboard (no Corne filter).
// CorneRawInput  raw input listener. Reports only keys that come from a
//                keyboard whose device name matches the Corne pattern, so the
//                laptop keyboard does not light up the overlay.
//
// Both put CorneKeyEvent items on CorneHook.Events; the overlay drains it on
// its UI timer.

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

public struct CorneKeyEvent {
    public int Vk;
    public bool Down;
    public bool Shift;
    public bool Signal;
}

public static class CorneHook {
    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll")]
    private static extern bool SetLayeredWindowAttributes(IntPtr hWnd, uint crKey, byte bAlpha, uint dwFlags);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    public static readonly ConcurrentQueue<CorneKeyEvent> Events = new ConcurrentQueue<CorneKeyEvent>();
    public static readonly HashSet<int> SignalVks = new HashSet<int>();
    public static bool AllKeys = false;

    private static LowLevelKeyboardProc proc = HookCallback;
    private static IntPtr hookId = IntPtr.Zero;
    private static bool lShift;
    private static bool rShift;

    public static bool Start() {
        if (hookId != IntPtr.Zero) {
            return true;
        }
        using (Process p = Process.GetCurrentProcess())
        using (ProcessModule m = p.MainModule) {
            hookId = SetWindowsHookEx(13, proc, GetModuleHandle(m.ModuleName), 0);
        }
        return hookId != IntPtr.Zero;
    }

    public static void Stop() {
        if (hookId != IntPtr.Zero) {
            UnhookWindowsHookEx(hookId);
            hookId = IntPtr.Zero;
        }
    }

    public static void MakeOverlayWindow(IntPtr hWnd, double opacity) {
        // layered + click-through + no taskbar/alt-tab + never takes focus
        int styles = GetWindowLong(hWnd, -20);
        styles |= 0x00080000 | 0x00000020 | 0x00000080 | 0x08000000;
        SetWindowLong(hWnd, -20, styles);
        // a layered window without an alpha set is drawn fully transparent
        SetLayeredWindowAttributes(hWnd, 0, (byte)Math.Round(opacity * 255), 0x2);
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0) {
            KBDLLHOOKSTRUCT k = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
            int msg = wParam.ToInt32();
            bool down = (msg == 0x100 || msg == 0x104);
            int vk = (int)k.vkCode;
            if (vk == 0xA0) { lShift = down; }
            else if (vk == 0xA1) { rShift = down; }

            CorneKeyEvent e = new CorneKeyEvent();
            e.Vk = vk;
            e.Down = down;
            e.Shift = lShift || rShift;
            e.Signal = SignalVks.Contains(vk);
            if (e.Signal || AllKeys) {
                Events.Enqueue(e);
            }
            if (e.Signal) {
                return (IntPtr)1;
            }
        }
        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }
}

public class CorneRawInput : NativeWindow, IDisposable {
    [StructLayout(LayoutKind.Sequential)]
    private struct RAWINPUTDEVICE {
        public ushort UsagePage;
        public ushort Usage;
        public uint Flags;
        public IntPtr Target;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RAWINPUTHEADER {
        public uint Type;
        public uint Size;
        public IntPtr Device;
        public IntPtr WParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RAWKEYBOARD {
        public ushort MakeCode;
        public ushort Flags;
        public ushort Reserved;
        public ushort VKey;
        public uint Message;
        public uint ExtraInformation;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RAWINPUTDEVICELIST {
        public IntPtr Device;
        public uint Type;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] devices, uint count, uint size);

    [DllImport("user32.dll")]
    private static extern uint GetRawInputData(IntPtr hRawInput, uint command, IntPtr data, ref uint size, uint headerSize);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint GetRawInputDeviceInfo(IntPtr device, uint command, StringBuilder data, ref uint size);

    [DllImport("user32.dll")]
    private static extern uint GetRawInputDeviceList([Out] RAWINPUTDEVICELIST[] list, ref uint count, uint size);

    private const int WM_INPUT = 0x00FF;
    private const uint RID_INPUT = 0x10000003;
    private const uint RIDI_DEVICENAME = 0x20000007;
    private const uint RIDEV_INPUTSINK = 0x00000100;
    private const uint RIM_TYPEKEYBOARD = 1;

    private readonly Regex deviceMatch;
    private readonly Dictionary<IntPtr, bool> isCorne = new Dictionary<IntPtr, bool>();
    private bool lShift;
    private bool rShift;

    public int KeyboardEvents;
    public int CorneEvents;

    public CorneRawInput(string devicePattern) {
        deviceMatch = new Regex(devicePattern, RegexOptions.IgnoreCase);

        CreateParams cp = new CreateParams();
        cp.Parent = new IntPtr(-3);   // HWND_MESSAGE: invisible, message-only window
        CreateHandle(cp);

        RAWINPUTDEVICE[] rid = new RAWINPUTDEVICE[1];
        rid[0].UsagePage = 0x01;      // generic desktop
        rid[0].Usage = 0x06;          // keyboard
        rid[0].Flags = RIDEV_INPUTSINK;
        rid[0].Target = Handle;
        if (!RegisterRawInputDevices(rid, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)))) {
            int error = Marshal.GetLastWin32Error();
            DestroyHandle();
            throw new System.ComponentModel.Win32Exception(error);
        }
    }

    public static string DeviceName(IntPtr device) {
        uint size = 1024;
        StringBuilder name = new StringBuilder((int)size);
        if (GetRawInputDeviceInfo(device, RIDI_DEVICENAME, name, ref size) == unchecked((uint)-1)) {
            return "";
        }
        return name.ToString();
    }

    public static string[] KeyboardNames() {
        uint count = 0;
        uint itemSize = (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICELIST));
        GetRawInputDeviceList(null, ref count, itemSize);
        RAWINPUTDEVICELIST[] list = new RAWINPUTDEVICELIST[count];
        GetRawInputDeviceList(list, ref count, itemSize);
        List<string> names = new List<string>();
        foreach (RAWINPUTDEVICELIST d in list) {
            if (d.Type == RIM_TYPEKEYBOARD) {
                names.Add(DeviceName(d.Device));
            }
        }
        return names.ToArray();
    }

    private bool IsCorne(IntPtr device) {
        if (device == IntPtr.Zero) {
            return false;   // injected input (SendInput) has no device
        }
        bool result;
        if (!isCorne.TryGetValue(device, out result)) {
            result = deviceMatch.IsMatch(DeviceName(device));
            isCorne[device] = result;
        }
        return result;
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_INPUT) {
            try {
                ReadInput(m.LParam);
            } catch {
                // never let a bad packet take down the message loop
            }
        }
        base.WndProc(ref m);
    }

    private void ReadInput(IntPtr hRawInput) {
        uint headerSize = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER));
        uint size = 0;
        GetRawInputData(hRawInput, RID_INPUT, IntPtr.Zero, ref size, headerSize);
        if (size == 0) {
            return;
        }
        IntPtr buffer = Marshal.AllocHGlobal((int)size);
        try {
            if (GetRawInputData(hRawInput, RID_INPUT, buffer, ref size, headerSize) != size) {
                return;
            }
            RAWINPUTHEADER header = (RAWINPUTHEADER)Marshal.PtrToStructure(buffer, typeof(RAWINPUTHEADER));
            if (header.Type != RIM_TYPEKEYBOARD) {
                return;
            }
            KeyboardEvents++;
            if (!IsCorne(header.Device)) {
                return;
            }
            CorneEvents++;

            RAWKEYBOARD kb = (RAWKEYBOARD)Marshal.PtrToStructure(
                new IntPtr(buffer.ToInt64() + headerSize), typeof(RAWKEYBOARD));
            int vk = kb.VKey;
            if (vk == 0 || vk == 0xFF) {
                return;
            }
            bool up = (kb.Flags & 0x1) != 0;    // RI_KEY_BREAK
            bool e0 = (kb.Flags & 0x2) != 0;    // RI_KEY_E0 (right-hand modifier)

            // raw input reports generic modifiers; the layout uses left/right codes
            if (vk == 0x10) { vk = (kb.MakeCode == 0x36) ? 0xA1 : 0xA0; }
            else if (vk == 0x11) { vk = e0 ? 0xA3 : 0xA2; }
            else if (vk == 0x12) { vk = e0 ? 0xA5 : 0xA4; }

            if (vk == 0xA0) { lShift = !up; }
            else if (vk == 0xA1) { rShift = !up; }

            CorneKeyEvent e = new CorneKeyEvent();
            e.Vk = vk;
            e.Down = !up;
            e.Shift = lShift || rShift;
            e.Signal = false;
            CorneHook.Events.Enqueue(e);
        } finally {
            Marshal.FreeHGlobal(buffer);
        }
    }

    public void Dispose() {
        DestroyHandle();
    }
}

// Battery level Windows keeps for a Bluetooth LE device (the value shown in
// Settings > Bluetooth & devices). For a ZMK split this is the central (left)
// half. Read from the device's BTHLE\DEV_<mac> node.
public static class CorneBattery {
    [StructLayout(LayoutKind.Sequential)]
    private struct DEVPROPKEY {
        public Guid fmtid;
        public uint pid;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SP_DEVINFO_DATA {
        public uint cbSize;
        public Guid ClassGuid;
        public uint DevInst;
        public IntPtr Reserved;
    }

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr SetupDiGetClassDevs(IntPtr classGuid, string enumerator, IntPtr hwndParent, uint flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiEnumDeviceInfo(IntPtr set, uint index, ref SP_DEVINFO_DATA data);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiGetDeviceInstanceId(IntPtr set, ref SP_DEVINFO_DATA data, StringBuilder id, int size, out int required);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiGetDevicePropertyW(IntPtr set, ref SP_DEVINFO_DATA data, ref DEVPROPKEY key, out uint type, byte[] buffer, uint size, out uint required, uint flags);

    [DllImport("setupapi.dll")]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);

    private const uint DIGCF_ALLCLASSES = 0x4;
    private static readonly Guid BatteryFmt = new Guid("104EA319-6EE2-4701-BD47-8DDBF425BBE5");    // pid 2: battery %
    private static readonly Guid ConnectedFmt = new Guid("83DA6326-97A6-4088-9453-A1923F573B29");  // pid 15: connected

    // Battery % of the Bluetooth LE device with this address (12 hex digits),
    // or -1 when unknown or not connected.
    public static int Read(string mac) {
        if (String.IsNullOrEmpty(mac)) {
            return -1;
        }
        IntPtr set = SetupDiGetClassDevs(IntPtr.Zero, "BTHLE", IntPtr.Zero, DIGCF_ALLCLASSES);
        if (set == new IntPtr(-1)) {
            return -1;
        }
        try {
            for (uint i = 0; ; i++) {
                SP_DEVINFO_DATA d = new SP_DEVINFO_DATA();
                d.cbSize = (uint)Marshal.SizeOf(typeof(SP_DEVINFO_DATA));
                if (!SetupDiEnumDeviceInfo(set, i, ref d)) {
                    break;
                }
                StringBuilder id = new StringBuilder(512);
                int required;
                if (!SetupDiGetDeviceInstanceId(set, ref d, id, id.Capacity, out required)) {
                    continue;
                }
                if (id.ToString().IndexOf("DEV_" + mac, StringComparison.OrdinalIgnoreCase) < 0) {
                    continue;
                }
                byte[] connected = GetProperty(set, ref d, ConnectedFmt, 15);
                if (connected == null || connected[0] == 0) {
                    return -1;
                }
                byte[] level = GetProperty(set, ref d, BatteryFmt, 2);
                return (level == null) ? -1 : level[0];
            }
        } finally {
            SetupDiDestroyDeviceInfoList(set);
        }
        return -1;
    }

    private static byte[] GetProperty(IntPtr set, ref SP_DEVINFO_DATA d, Guid fmtid, uint pid) {
        DEVPROPKEY key = new DEVPROPKEY();
        key.fmtid = fmtid;
        key.pid = pid;
        byte[] buffer = new byte[16];
        uint type;
        uint required;
        if (!SetupDiGetDevicePropertyW(set, ref d, ref key, out type, buffer, (uint)buffer.Length, out required, 0) || required == 0) {
            return null;
        }
        return buffer;
    }
}
