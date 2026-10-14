using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;

namespace WaterFields.Export;

internal static class NativeExports {
    private const int StateIdle = 0;
    private const int StateRunning = 1;
    private const int StateSucceeded = 2;
    private const int StateFailed = 3;
    private const int StateTimedOut = 4;

    private const int StartAccepted = 0;
    private const int StartBusy = 1;
    private const int StartRejected = 2;

    // PIN keeps Native AOT loaded until process exit; it does not support unloading.
    private const uint ModuleFlagPin = 0x00000001;
    // FROM_ADDRESS finds this DLL through the Start function's address.
    private const uint ModuleFlagFromAddress = 0x00000004;

    private static readonly object Gate = new();
    private static int state = StateIdle;
    private static nint lzo;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetModuleHandleExW(uint flags, nint address, out nint module);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern uint GetModuleFileNameW(nint module, StringBuilder path, int capacity);

    private static unsafe void PinLibrary() {
        if (lzo != 0) {
            return;
        }

        var startAddress = (nint)(delegate* unmanaged[Cdecl]<nint, int>)&Start;
        uint flags = ModuleFlagPin | ModuleFlagFromAddress;

        if (!GetModuleHandleExW(flags, startAddress, out var module)) {
            throw new IOException("Could not retain the export library.");
        }

        var path = new StringBuilder(32768);
        var length = GetModuleFileNameW(module, path, path.Capacity);

        if (length == 0 || length >= path.Capacity) {
            throw new IOException("Could not locate the export library.");
        }

        string directory = Path.GetDirectoryName(path.ToString())!;
        lzo = NativeLibrary.Load(Path.Combine(directory, "liblzo2.dll"));
    }

    [UnmanagedCallersOnly(EntryPoint = "WaterFields_StartExportV1", CallConvs = [typeof(CallConvCdecl)])]
    private static int Start(nint requestUtf8) {
        lock (Gate) {
            if (state == StateRunning) {
                return StartBusy;
            }

            FileStream? result = null;

            try {
                PinLibrary();

                var request = Marshal.PtrToStringUTF8(requestUtf8);

                if (string.IsNullOrWhiteSpace(request)) {
                    return StartRejected;
                }

                request = Path.GetFullPath(request);
                result = new FileStream(request + ".result.json", FileMode.CreateNew, FileAccess.Write, FileShare.Read);

                state = StateRunning;
                var destination = result;
                _ = Task.Run(() => Run(request, destination));

                return StartAccepted;
            } catch {
                result?.Dispose();
                state = StateFailed;

                return StartRejected;
            }
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "WaterFields_ExportStateV1", CallConvs = [typeof(CallConvCdecl)])]
    private static int State() {
        try {
            lock (Gate) {
                PinLibrary();
            }

            return Volatile.Read(ref state);
        } catch {
            return StateFailed;
        }
    }

    private static void Run(string request, FileStream destination) {
        JsonObject result;
        var finalState = StateSucceeded;

        try {
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            result = Program.Run(request, deadline.Token);
        } catch (Exception e) {
            bool timedOut = e is OperationCanceledException;
            finalState = timedOut ? StateTimedOut : StateFailed;

            result = new JsonObject {
                ["schema"] = "waterfields-export-result-v1",
                ["status"] = timedOut ? "timed-out" : "failed",
                ["error"] = timedOut ?
                    "Export timed out; inspect the output before retrying." :
                    e.Message
            };
        }

        try {
            using (destination) {
                var resultBytes = Encoding.UTF8.GetBytes(result.ToJsonString());
                destination.Write(resultBytes);
                destination.Flush(true);
            }
        } catch {
            finalState = StateFailed;
        } finally {
            Volatile.Write(ref state, finalState);
        }
    }
}
