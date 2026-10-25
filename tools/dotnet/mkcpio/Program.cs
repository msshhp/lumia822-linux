// mkcpio: builds a gzip-compressed newc initramfs.
//   mkcpio <out.cpio.gz> <busybox> <init>
// Layout: /bin/busybox, /init, /bin /dev /proc /sys /tmp, /dev/console (5:1), /dev/tty0 (4:0)
using System;
using System.IO;
using System.IO.Compression;
using System.Text;

static class Program
{
    static int ino = 1;

    static void Entry(Stream s, string name, uint mode, byte[] data, uint rdevMajor = 0, uint rdevMinor = 0)
    {
        data ??= Array.Empty<byte>();
        string hdr = "070701" + H(ino++) + H(mode) + H(0) + H(0) + H(1) + H(0) + H((uint)data.Length)
                   + H(0) + H(0) + H(rdevMajor) + H(rdevMinor) + H((uint)name.Length + 1) + H(0);
        W(s, Encoding.ASCII.GetBytes(hdr)); W(s, Encoding.ASCII.GetBytes(name)); s.WriteByte(0); Pad(s);
        W(s, data); Pad(s);
    }
    static string H(uint v) => v.ToString("x8");
    static string H(int v) => ((uint)v).ToString("x8");
    static void W(Stream s, byte[] b) => s.Write(b, 0, b.Length);
    static void Pad(Stream s) { while (s.Position % 4 != 0) s.WriteByte(0); }

    static int Main(string[] a)
    {
        var raw = new MemoryStream();
        foreach (var d in new[] { "bin", "dev", "proc", "sys", "tmp" }) Entry(raw, d, 0x41ED, null); // dir 0755
        Entry(raw, "dev/console", 0x2180, null, 5, 1);   // char 0600
        Entry(raw, "dev/tty0", 0x2180, null, 4, 0);
        Entry(raw, "bin/busybox", 0x81ED, File.ReadAllBytes(a[1]));                 // file 0755
        Entry(raw, "bin/sh", 0xA1FF, Encoding.ASCII.GetBytes("busybox"));            // symlink
        Entry(raw, "init", 0x81ED, Encoding.ASCII.GetBytes(File.ReadAllText(a[2]).Replace("\r\n", "\n")));
        if (a.Length > 4) // optional directory of extra executables -> /bin/
        {
            foreach (var f in Directory.GetFiles(a[4]))
                Entry(raw, "bin/" + Path.GetFileName(f), 0x81ED, File.ReadAllBytes(f));
        }
        if (a.Length > 3 && Directory.GetFiles(a[3]).Length > 0) // optional directory of kernel modules -> /lib/modules/
        {
            Entry(raw, "lib", 0x41ED, null);
            Entry(raw, "lib/modules", 0x41ED, null);
            foreach (var f in Directory.GetFiles(a[3]))
                Entry(raw, "lib/modules/" + Path.GetFileName(f), 0x81A4, File.ReadAllBytes(f));
        }
        Entry(raw, "TRAILER!!!", 0, null);
        using var outf = File.Create(a[0]);
        using var gz = new GZipStream(outf, CompressionLevel.Optimal);
        raw.Position = 0; raw.CopyTo(gz);
        Console.WriteLine("raw cpio " + raw.Length + " bytes");
        return 0;
    }
}
