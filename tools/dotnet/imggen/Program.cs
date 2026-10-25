// imggen: reproduces the image-generation half of WPinternals' Spec A bootloader unlock
// (LumiaV1UnlockFirmware), writing each blob to disk instead of flashing it.
//   imggen <rm845.ffu> <phone_boot_area.bin> <engineering_sbl3.bin|-> <outdir>
using System;
using System.IO;
using System.Linq;

namespace WPinternals
{
    internal enum LogType { FileOnly, FileAndConsole, ConsoleOnly }

    internal static class LogFile
    {
        public static void Log(string m, LogType t = LogType.FileOnly) => Console.WriteLine("log: " + m);
        public static void LogException(Exception e, LogType t = LogType.FileAndConsole, string s = null) => Console.WriteLine("exception: " + e);
    }

    internal class ProgressUpdater
    {
        public ProgressUpdater(ulong max, Action<int, TimeSpan?> cb) { }
        public void IncreaseProgress(ulong n) { }
        public void SetProgress(ulong n) { }
    }

    internal static class Program
    {
        // imggen nv <current_gpt_34_sectors.bin> <SBA asset> <outdir>
        // Same steps as the first part of LumiaUnlockUEFI: move UEFI_BS_NV aside and place the
        // Secure-Boot-disabled NV image (SBA) in a new UEFI_BS_NV right after it.
        private static int Nv(string[] args)
        {
            string outDir = args[3];
            Directory.CreateDirectory(outDir);
            byte[] gptBytes = File.ReadAllBytes(args[1]);
            GPT gpt = new(gptBytes);
            Partition backup = gpt.GetPartition("BACKUP_BS_NV");
            if (backup != null) throw new Exception("BACKUP_BS_NV already present");
            backup = gpt.GetPartition("UEFI_BS_NV");
            Guid type = backup.PartitionTypeGuid, guid = backup.PartitionGuid;
            backup.Name = "BACKUP_BS_NV";
            backup.PartitionGuid = Guid.NewGuid();
            backup.PartitionTypeGuid = Guid.NewGuid();
            Partition nv = new()
            {
                Name = "UEFI_BS_NV",
                Attributes = backup.Attributes,
                PartitionGuid = guid,
                PartitionTypeGuid = type,
                FirstSector = backup.LastSector + 1
            };
            nv.LastSector = nv.FirstSector + backup.LastSector - backup.FirstSector;
            gpt.Partitions.Add(nv);
            byte[] newGpt = gpt.Rebuild();

            using MemoryStream sba = new();
            using (Stream s = new HelperClasses.DecompressedStream(File.OpenRead(args[2]))) s.CopyTo(sba);

            File.WriteAllBytes(Path.Combine(outDir, "GPT_NV.bin"), newGpt);
            File.WriteAllBytes(Path.Combine(outDir, "SBA_NV.bin"), sba.ToArray());
            Console.WriteLine($"BACKUP_BS_NV {backup.FirstSector}-{backup.LastSector}");
            Console.WriteLine($"UEFI_BS_NV   {nv.FirstSector}-{nv.LastSector} ({(nv.LastSector - nv.FirstSector + 1) * 512} bytes)");
            Console.WriteLine($"SBA image    {sba.Length} bytes -> write at lba {nv.FirstSector}");
            foreach (Partition p in gpt.Partitions.Where(p => p.FirstSector > 90000 && p.FirstSector < 110000))
                Console.WriteLine($"  gpt {p.Name,-14} {p.FirstSector}-{p.LastSector}");
            return 0;
        }

        private static int Main(string[] args)
        {
            if (args[0] == "nv") return Nv(args);
            string ffuPath = args[0], dumpPath = args[1], sbl3Path = args[2] == "-" ? null : args[2], outDir = args[3];
            Directory.CreateDirectory(outDir);
            FFU ffu = new(ffuPath);
            Console.WriteLine("FFU firmware: " + ffu.GetFirmwareVersion());

            byte[] dump = File.ReadAllBytes(dumpPath);
            byte[] Sectors(ulong first, ulong count) => dump.Skip((int)(first * 512)).Take((int)(count * 512)).ToArray();

            // Compare boot partitions on the phone with the FFU, using the phone's GPT
            GPT phoneGpt = new(Sectors(0, 34));
            foreach (string name in new[] { "SBL1", "SBL2", "SBL3", "UEFI", "TZ", "RPM", "WINSECAPP" })
            {
                Partition p = phoneGpt.GetPartition(name);
                byte[] ffuPart = ffu.GetPartition(name);
                byte[] phonePart = Sectors(p.FirstSector, (ulong)ffuPart.Length / 512);
                Console.WriteLine($"compare {name,-10} phone@{p.FirstSector} len={ffuPart.Length} identical={ffuPart.SequenceEqual(phonePart)}");
            }

            // --- Same steps as LumiaV1UnlockFirmware ---
            // RestoreBackupPartitions() is skipped on purpose: it only exists to keep partitions within the
            // emergency programmer's address range, and we write through Windows instead.
            GPT NewGPT = new(Sectors(0, 34));
            byte[] GPTBytes = NewGPT.InsertHack();
            if (sbl3Path != null && NewGPT.GetPartition("IS_UNLOCKED_SBL3") == null)
            {
                NewGPT.Partitions.Add(new Partition
                {
                    Name = "IS_UNLOCKED_SBL3",
                    Attributes = 0,
                    PartitionGuid = Guid.NewGuid(),
                    PartitionTypeGuid = Guid.NewGuid(),
                    FirstSector = 0x40,
                    LastSector = 0x40
                });
                GPTBytes = NewGPT.Rebuild();
            }

            SBL1 sbl1 = new(ffu.GetPartition("SBL1"));
            SBL2 sbl2Part = new(ffu.GetPartition("SBL2"));
            byte[] SBL2 = sbl2Part.Patch();
            byte[] header = new byte[0x0C];
            Buffer.BlockCopy(sbl2Part.Binary, 0, header, 0, 0x0C);
            byte[] ExtraSector = sbl1.GenerateExtraSector(header);

            SBL3 original = new(ffu.GetPartition("SBL3"));
            SBL3 sbl3Part = sbl3Path == null ? original : new SBL3(sbl3Path);
            if (sbl3Part.Binary.Length > original.Binary.Length) throw new Exception("Selected SBL3 is too large.");
            byte[] SBL3 = sbl3Part.Patch();

            UEFI uefiPart = new(ffu.GetPartition("UEFI"));
            byte[] UEFIBytes = uefiPart.Patch();
            byte[] MBR = ffu.GetSectors(0, 1);

            Console.WriteLine("RKH from FFU SBL1: " + HelperClasses.Converter.ConvertHexToString(sbl1.RootKeyHash, ""));

            void Emit(string name, byte[] data, ulong lba)
            {
                File.WriteAllBytes(Path.Combine(outDir, name + ".bin"), data);
                Console.WriteLine($"write {name,-6} lba={lba} sectors={data.Length / 512.0}");
            }
            Emit("MBR", MBR, 0);
            Emit("GPT", GPTBytes, 0); // buffer as read from sector 0 (EFI PART header at offset 0x200)
            Emit("HACK", ExtraSector, NewGPT.GetPartition("HACK").FirstSector);
            Emit("SBL2", SBL2, NewGPT.GetPartition("SBL2").FirstSector);
            Emit("SBL3", SBL3, NewGPT.GetPartition("SBL3").FirstSector);
            Emit("UEFI", UEFIBytes, NewGPT.GetPartition("UEFI").FirstSector);
            foreach (Partition p in NewGPT.Partitions)
                Console.WriteLine($"  gpt {p.Name,-18} {p.FirstSector,-8} {p.LastSector,-8} {p.PartitionTypeGuid}");
            return 0;
        }
    }
}
