using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;

namespace WaterFields.Export;

internal static class NativeExports
{
    private const int stateIdle = 0;
    private const int stateRunning = 1;
    private const int stateSucceeded = 2;
    private const int stateFailed = 3;
    private const int stateTimedOut = 4;

    private const int startAccepted = 0;
    private const int startBusy = 1;
    private const int startRejected = 2;

    private const uint moduleFlagPin = 0x00000001;
    private const uint moduleFlagFromAddress = 0x00000004;

    private static readonly object gate = new();
    private static int state = stateIdle;
    private static nint lzo;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetModuleHandleExW(uint flags, nint address, out nint module);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern uint GetModuleFileNameW(nint module, StringBuilder path, int capacity);

    private static unsafe void PinLibrary()
    {
        if (lzo != 0)
        {
            return;
        }

        var startAddress = (nint)(delegate* unmanaged[Cdecl]<nint, int>)&Start;
        uint flags = moduleFlagPin | moduleFlagFromAddress;

        if (!GetModuleHandleExW(flags, startAddress, out var module))
        {
            throw new IOException("Could not retain the export library.");
        }

        var path = new StringBuilder(32768);
        var length = GetModuleFileNameW(module, path, path.Capacity);

        if (length == 0 || length >= path.Capacity)
        {
            throw new IOException("Could not locate the export library.");
        }

        string directory = Path.GetDirectoryName(path.ToString())!;
        lzo = NativeLibrary.Load(Path.Combine(directory, "liblzo2.dll"));
    }

    [UnmanagedCallersOnly(EntryPoint = "WaterFields_StartExportV1", CallConvs = [typeof(CallConvCdecl)])]
    private static int Start(nint requestUtf8)
    {
        lock (gate)
        {
            if (state == stateRunning)
            {
                return startBusy;
            }

            FileStream? result = null;

            try
            {
                PinLibrary();

                var request = Marshal.PtrToStringUTF8(requestUtf8);

                if (string.IsNullOrWhiteSpace(request))
                {
                    return startRejected;
                }

                request = Path.GetFullPath(request);
                result = new FileStream(request + ".result.json", FileMode.CreateNew, FileAccess.Write, FileShare.Read);

                state = stateRunning;
                var destination = result;
                _ = Task.Run(() => Run(request, destination));

                return startAccepted;
            }
            catch
            {
                result?.Dispose();
                state = stateFailed;

                return startRejected;
            }
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "WaterFields_ExportStateV1", CallConvs = [typeof(CallConvCdecl)])]
    private static int State()
    {
        try
        {
            lock (gate)
            {
                PinLibrary();
            }

            return Volatile.Read(ref state);
        }
        catch
        {
            return stateFailed;
        }
    }

    private static void Run(string request, FileStream destination)
    {
        JsonObject result;
        var finalState = stateSucceeded;

        try
        {
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            result = Program.Run(request, deadline.Token);
        }
        catch (Exception e)
        {
            bool timedOut = e is OperationCanceledException;
            finalState = timedOut ? stateTimedOut : stateFailed;

            result = new JsonObject
            {
                ["schema"] = "waterfields-export-result-v1",
                ["status"] = timedOut ? "timed-out" : "failed",
                ["error"] = timedOut ?
                    "Export timed out; inspect the output before retrying." :
                    e.Message
            };
        }

        try
        {
            using (destination)
            {
                var resultBytes = Encoding.UTF8.GetBytes(result.ToJsonString());
                destination.Write(resultBytes);
                destination.Flush(true);
            }
        }
        catch
        {
            finalState = stateFailed;
        }
        finally
        {
            Volatile.Write(ref state, finalState);
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "WaterFields_SavePulseV1", CallConvs = [typeof(CallConvCdecl)])]
    private static int SavePulse(nint requestUtf8)
    {
        try
        {
            lock (gate)
            {
                PinLibrary();
            }
            SaveGuard.Pulse(Marshal.PtrToStringUTF8(requestUtf8) ?? "");
            return startAccepted;
        }
        catch
        {
            return startRejected;
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "WaterFields_SaveStopV1", CallConvs = [typeof(CallConvCdecl)])]
    private static int SaveStop()
    {
        SaveGuard.Stop();
        return startAccepted;
    }
}
