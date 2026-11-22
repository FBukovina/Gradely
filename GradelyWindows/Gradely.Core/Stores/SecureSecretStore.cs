using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace Gradely.Core.Stores;

/// <summary>
/// Encrypts sensitive credentials and tokens per-user using native Windows DPAPI (crypt32.dll).
/// </summary>
public sealed class SecureSecretStore
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("Gradey.Windows.DPAPI.v1");
    private readonly string _secretsDirectory;
    private readonly JsonSerializerOptions _jsonOptions = new() { WriteIndented = false };

    public SecureSecretStore(string? baseDirectory = null)
    {
        var root = baseDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Gradey");
        _secretsDirectory = Path.Combine(root, "secrets");
    }

    public void Save<T>(string key, T value)
    {
        Directory.CreateDirectory(_secretsDirectory);
        var json = JsonSerializer.Serialize(value, _jsonOptions);
        var plainBytes = Encoding.UTF8.GetBytes(json);
        var protectedBytes = Protect(plainBytes);
        var path = PathForKey(key);
        var tempPath = path + ".tmp";
        File.WriteAllBytes(tempPath, protectedBytes);
        File.Move(tempPath, path, overwrite: true);
    }

    public T? Load<T>(string key)
    {
        var path = PathForKey(key);
        if (!File.Exists(path)) return default;
        try
        {
            var protectedBytes = File.ReadAllBytes(path);
            var plainBytes = Unprotect(protectedBytes);
            var json = Encoding.UTF8.GetString(plainBytes);
            return JsonSerializer.Deserialize<T>(json, _jsonOptions);
        }
        catch
        {
            return default;
        }
    }

    public void Delete(string key)
    {
        var path = PathForKey(key);
        if (File.Exists(path))
            File.Delete(path);
    }

    private string PathForKey(string key)
    {
        var safe = string.Concat(key.Select(c => char.IsLetterOrDigit(c) || c is '-' or '_' ? c : '_'));
        return Path.Combine(_secretsDirectory, safe + ".bin");
    }

    private static byte[] Protect(byte[] plainBytes)
    {
        if (!OperatingSystem.IsWindows())
            return plainBytes;

        return DpapiNative.Protect(plainBytes, Entropy);
    }

    private static byte[] Unprotect(byte[] protectedBytes)
    {
        if (!OperatingSystem.IsWindows())
            return protectedBytes;

        return DpapiNative.Unprotect(protectedBytes, Entropy);
    }

    private static class DpapiNative
    {
        private const int CryptProtectUiForbidden = 0x01;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DataBlob
        {
            public int cbData;
            public nint pbData;
        }

        [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CryptProtectData(
            ref DataBlob pDataIn,
            string? szDataDescr,
            ref DataBlob pOptionalEntropy,
            nint pvReserved,
            nint pPromptStruct,
            int dwFlags,
            out DataBlob pDataOut);

        [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CryptUnprotectData(
            ref DataBlob pDataIn,
            nint ppszDataDescr,
            ref DataBlob pOptionalEntropy,
            nint pvReserved,
            nint pPromptStruct,
            int dwFlags,
            out DataBlob pDataOut);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern nint LocalFree(nint hMem);

        public static byte[] Protect(byte[] data, byte[] entropy)
        {
            var dataIn = CreateBlob(data);
            var entropyBlob = CreateBlob(entropy);
            var dataOut = new DataBlob();
            try
            {
                if (!CryptProtectData(ref dataIn, "GradeySecret", ref entropyBlob, 0, 0, CryptProtectUiForbidden, out dataOut))
                    throw new InvalidOperationException($"CryptProtectData failed with error {Marshal.GetLastWin32Error()}.");

                var result = new byte[dataOut.cbData];
                Marshal.Copy(dataOut.pbData, result, 0, dataOut.cbData);
                return result;
            }
            finally
            {
                FreeUnmanagedBlob(dataIn);
                FreeUnmanagedBlob(entropyBlob);
                if (dataOut.pbData != 0) LocalFree(dataOut.pbData);
            }
        }

        public static byte[] Unprotect(byte[] data, byte[] entropy)
        {
            var dataIn = CreateBlob(data);
            var entropyBlob = CreateBlob(entropy);
            var dataOut = new DataBlob();
            try
            {
                if (!CryptUnprotectData(ref dataIn, 0, ref entropyBlob, 0, 0, CryptProtectUiForbidden, out dataOut))
                    throw new InvalidOperationException($"CryptUnprotectData failed with error {Marshal.GetLastWin32Error()}.");

                var result = new byte[dataOut.cbData];
                Marshal.Copy(dataOut.pbData, result, 0, dataOut.cbData);
                return result;
            }
            finally
            {
                FreeUnmanagedBlob(dataIn);
                FreeUnmanagedBlob(entropyBlob);
                if (dataOut.pbData != 0) LocalFree(dataOut.pbData);
            }
        }

        private static DataBlob CreateBlob(byte[] bytes)
        {
            var ptr = Marshal.AllocHGlobal(bytes.Length);
            Marshal.Copy(bytes, 0, ptr, bytes.Length);
            return new DataBlob { cbData = bytes.Length, pbData = ptr };
        }

        private static void FreeUnmanagedBlob(DataBlob blob)
        {
            if (blob.pbData != 0) Marshal.FreeHGlobal(blob.pbData);
        }
    }
}
