// LinuxLoader: a Windows Boot Manager application for Lumia (ARMv7) that starts a Linux kernel
// through its EFI stub.
//
// Boot flow: bootmgr -> BlApplicationEntry (this file) -> switch back to the firmware's MMU/exception
// context (same steps as imbushuo's BootShim) -> efi_main:
//   - reads \linux\zImage, \linux\lumia822.dtb, \linux\initramfs.gz from whichever volume has them
//   - installs the DTB as the EFI device-tree configuration table
//   - exposes the initramfs through the LINUX_EFI_INITRD_MEDIA LoadFile2 protocol
//   - LoadImage/StartImage the kernel with the command line from \linux\cmdline.txt (or a default)
//
// Constraints found on the Lumia 822 firmware: no NEON/VFP code (build with -mfpu=none and no
// vectorization), and no writes to the image's own .data after the context switch, so all mutable
// state lives on the stack or in pool memory.
#include <stdint.h>
#include <stddef.h>

typedef uint16_t CHAR16;
typedef void *EFI_HANDLE;
typedef uintptr_t EFI_STATUS;
typedef uintptr_t UINTN;
typedef struct { uint32_t d1; uint16_t d2, d3; uint8_t d4[8]; } EFI_GUID;

#define EFI_SUCCESS 0
#define EFI_ERR(x) ((EFI_STATUS)(0x80000000u | (x)))
#define EFI_BUFFER_TOO_SMALL EFI_ERR(5)
#define EFI_NOT_FOUND EFI_ERR(14)
#define EFI_ERROR(s) (((intptr_t)(s)) < 0)

typedef struct { uint64_t Signature; uint32_t Revision, HeaderSize, CRC32, Reserved; } EFI_TABLE_HEADER;

typedef struct SIMPLE_TEXT_OUTPUT {
    EFI_STATUS (*Reset)(struct SIMPLE_TEXT_OUTPUT *, uint8_t);
    EFI_STATUS (*OutputString)(struct SIMPLE_TEXT_OUTPUT *, const CHAR16 *);
} SIMPLE_TEXT_OUTPUT;

typedef struct {
    EFI_TABLE_HEADER Hdr;
    void *RaiseTPL, *RestoreTPL;
    EFI_STATUS (*AllocatePages)(int Type, int MemType, UINTN Pages, uint64_t *Memory);
    void *FreePages;
    EFI_STATUS (*GetMemoryMap)(UINTN *Size, void *Map, UINTN *Key, UINTN *DescSize, uint32_t *DescVersion);
    EFI_STATUS (*AllocatePool)(int MemType, UINTN Size, void **Buffer);
    EFI_STATUS (*FreePool)(void *);
    void *CreateEvent, *SetTimer, *WaitForEvent, *SignalEvent, *CloseEvent, *CheckEvent;
    void *InstallProtocolInterface, *ReinstallProtocolInterface, *UninstallProtocolInterface;
    EFI_STATUS (*HandleProtocol)(EFI_HANDLE, const EFI_GUID *, void **);
    void *Reserved, *RegisterProtocolNotify, *LocateHandle, *LocateDevicePath;
    EFI_STATUS (*InstallConfigurationTable)(const EFI_GUID *, void *);
    EFI_STATUS (*LoadImage)(uint8_t BootPolicy, EFI_HANDLE Parent, void *DevicePath, void *Source, UINTN Size, EFI_HANDLE *Image);
    EFI_STATUS (*StartImage)(EFI_HANDLE, UINTN *ExitDataSize, CHAR16 **ExitData);
    void *Exit, *UnloadImage, *ExitBootServices, *GetNextMonotonicCount;
    EFI_STATUS (*Stall)(UINTN Microseconds);
    void *SetWatchdogTimer;
    void *ConnectController, *DisconnectController, *OpenProtocol, *CloseProtocol, *OpenProtocolInformation, *ProtocolsPerHandle;
    EFI_STATUS (*LocateHandleBuffer)(int SearchType, const EFI_GUID *, void *Key, UINTN *Count, EFI_HANDLE **Buffer);
    EFI_STATUS (*LocateProtocol)(const EFI_GUID *, void *Registration, void **Interface);
    EFI_STATUS (*InstallMultipleProtocolInterfaces)(EFI_HANDLE *, ...);
} EFI_BOOT_SERVICES;

typedef struct {
    EFI_TABLE_HEADER Hdr;
    CHAR16 *FirmwareVendor;
    uint32_t FirmwareRevision;
    EFI_HANDLE ConsoleInHandle; void *ConIn;
    EFI_HANDLE ConsoleOutHandle; SIMPLE_TEXT_OUTPUT *ConOut;
    EFI_HANDLE StandardErrorHandle; void *StdErr;
    void *RuntimeServices;
    EFI_BOOT_SERVICES *BootServices;
} EFI_SYSTEM_TABLE;

typedef struct {
    uint32_t Revision;
    EFI_HANDLE ParentHandle;
    EFI_SYSTEM_TABLE *SystemTable;
    EFI_HANDLE DeviceHandle;
    void *FilePath, *Reserved;
    uint32_t LoadOptionsSize;
    void *LoadOptions;
} EFI_LOADED_IMAGE;

typedef struct EFI_FILE {
    uint64_t Revision;
    EFI_STATUS (*Open)(struct EFI_FILE *, struct EFI_FILE **, const CHAR16 *, uint64_t Mode, uint64_t Attr);
    EFI_STATUS (*Close)(struct EFI_FILE *);
    void *Delete;
    EFI_STATUS (*Read)(struct EFI_FILE *, UINTN *Size, void *Buffer);
    void *Write;
    EFI_STATUS (*GetPosition)(struct EFI_FILE *, uint64_t *);
    EFI_STATUS (*SetPosition)(struct EFI_FILE *, uint64_t);
} EFI_FILE;

typedef struct { uint64_t Revision; EFI_STATUS (*OpenVolume)(void *This, EFI_FILE **Root); } EFI_SIMPLE_FS;

// LoadFile2 protocol instance followed by the data it serves (the protocol pointer is the first field,
// so the callback can reach the data from This)
typedef struct INITRD_LOADER {
    EFI_STATUS (*LoadFile)(struct INITRD_LOADER *, void *FilePath, uint8_t BootPolicy, UINTN *Size, void *Buffer);
    const uint8_t *Data;
    UINTN Size;
} INITRD_LOADER;

static const EFI_GUID LoadedImageGuid = {0x5B1B31A1, 0x9562, 0x11d2, {0x8E, 0x3F, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B}};
static const EFI_GUID SimpleFsGuid = {0x964E5B22, 0x6459, 0x11d2, {0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B}};
static const EFI_GUID DevicePathGuid = {0x09576E91, 0x6D3F, 0x11d2, {0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B}};
static const EFI_GUID LoadFile2Guid = {0x4006c0c1, 0xfcb3, 0x403e, {0x99, 0x6d, 0x4a, 0x6c, 0x87, 0x24, 0xe0, 0x6d}};
static const EFI_GUID DeviceTreeGuid = {0xb1b621d5, 0xf19c, 0x41a5, {0x83, 0x0b, 0xd9, 0x15, 0x2c, 0x69, 0xaa, 0xe0}};
static const EFI_GUID GopGuid = {0x9042a9de, 0x23dc, 0x4a38, {0x96, 0xfb, 0x7a, 0xde, 0xd0, 0x80, 0x51, 0x6a}};

typedef struct {
    uint32_t Version, HorizontalResolution, VerticalResolution, PixelFormat;
    uint32_t PixelMask[4];
    uint32_t PixelsPerScanLine;
} GOP_MODE_INFO;
typedef struct {
    uint32_t MaxMode, Mode;
    GOP_MODE_INFO *Info;
    UINTN SizeOfInfo;
    uint64_t FrameBufferBase;
    UINTN FrameBufferSize;
} GOP_MODE;
typedef struct { void *QueryMode, *SetMode, *Blt; GOP_MODE *Mode; } GOP;

// Vendor media device path with LINUX_EFI_INITRD_MEDIA_GUID, followed by an end node
static const struct __attribute__((packed)) {
    uint8_t Type, SubType; uint16_t Length; EFI_GUID Guid;
    uint8_t EndType, EndSubType; uint16_t EndLength;
} InitrdDevicePath = {4, 3, 20, {0x5568e427, 0x68fc, 0x4f3d, {0xac, 0x74, 0xca, 0x55, 0x52, 0x31, 0xcc, 0x68}}, 0x7f, 0xff, 4};

// Relocation-parity pad: the Lumia boot manager only loads images whose base-relocation block ends
// with an ABSOLUTE padding entry (odd number of real fixups). Toggle RELOC_PAD so the count is odd.
#ifdef RELOC_PAD
__attribute__((used)) static const void *const RelocPad = &RelocPad;
#endif

static const char DefaultCmdline[] =
    "console=tty0 clk_ignore_unused pd_ignore_unused nosmp efi=debug,noruntime,novamap loglevel=8 ignore_loglevel rdinit=/init";

void *memset(void *d, int c, size_t n) { volatile uint8_t *p = d; while (n--) *p++ = (uint8_t)c; return d; }
void *memcpy(void *d, const void *s, size_t n) { volatile uint8_t *p = d; const uint8_t *q = s; while (n--) *p++ = *q++; return d; }

typedef struct { EFI_SYSTEM_TABLE *ST; EFI_BOOT_SERVICES *BS; } CTX;

// The firmware console only gets drawn while the CPU idles, so pause after every message; otherwise a
// later hang would leave nothing on screen.
static void Say(CTX *c, const CHAR16 *s)
{
    c->ST->ConOut->OutputString(c->ST->ConOut, s);
    c->BS->Stall(1000 * 1000);
}

static void SayHex(CTX *c, const CHAR16 *label, uintptr_t v)
{
    CHAR16 b[16];
    Say(c, label);
    b[0] = u'0'; b[1] = u'x';
    for (int i = 0; i < 8; i++) b[2 + i] = (CHAR16)"0123456789abcdef"[(v >> (28 - 4 * i)) & 15];
    b[10] = u'\r'; b[11] = u'\n'; b[12] = 0;
    Say(c, b);
}

static EFI_STATUS InitrdLoadFile(INITRD_LOADER *This, void *FilePath, uint8_t BootPolicy, UINTN *Size, void *Buffer)
{
    if (BootPolicy) return EFI_ERR(3); // EFI_UNSUPPORTED
    if (!Buffer || *Size < This->Size) { *Size = This->Size; return EFI_BUFFER_TOO_SMALL; }
    memcpy(Buffer, This->Data, This->Size);
    *Size = This->Size;
    return EFI_SUCCESS;
}

static EFI_STATUS ReadFile(CTX *c, EFI_FILE *Root, const CHAR16 *Path, void **Data, UINTN *Size)
{
    EFI_FILE *f;
    EFI_STATUS s = Root->Open(Root, &f, Path, 1 /* read */, 0);
    if (EFI_ERROR(s)) return s;
    uint64_t end = 0;
    f->SetPosition(f, 0xFFFFFFFFFFFFFFFFull);
    f->GetPosition(f, &end);
    f->SetPosition(f, 0);
    *Size = (UINTN)end;
    s = c->BS->AllocatePool(2 /* EfiLoaderData */, *Size + 1, Data);
    if (!EFI_ERROR(s)) s = f->Read(f, Size, *Data);
    f->Close(f);
    return s;
}

static EFI_STATUS efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable)
{
    CTX ctx = {SystemTable, SystemTable->BootServices}, *c = &ctx;
    EFI_BOOT_SERVICES *BS = ctx.BS;
    EFI_STATUS s;

    Say(c, u"\r\n\r\nLinuxLoader for Lumia 822\r\n[1] locate volumes\r\n");
    UINTN count = 0; EFI_HANDLE *handles = NULL; EFI_FILE *root = NULL; EFI_HANDLE fsHandle = NULL;
    s = BS->LocateHandleBuffer(2 /* ByProtocol */, &SimpleFsGuid, NULL, &count, &handles);
    if (EFI_ERROR(s)) { SayHex(c, u"LocateHandleBuffer failed ", s); return s; }
    SayHex(c, u"[2] volumes: ", count);

    void *kernel = NULL; UINTN kernelSize = 0;
    for (UINTN i = 0; i < count && !kernel; i++) {
        EFI_SIMPLE_FS *fs;
        if (EFI_ERROR(BS->HandleProtocol(handles[i], &SimpleFsGuid, (void **)&fs))) continue;
        if (EFI_ERROR(fs->OpenVolume(fs, &root))) continue;
        if (!EFI_ERROR(ReadFile(c, root, u"\\linux\\zImage", &kernel, &kernelSize))) fsHandle = handles[i];
        else kernel = NULL;
    }
    if (!kernel) { Say(c, u"\\linux\\zImage not found on any volume\r\n"); return EFI_NOT_FOUND; }
    SayHex(c, u"[3] kernel size ", kernelSize);

    void *dtb = NULL; UINTN dtbSize = 0;
    s = ReadFile(c, root, u"\\linux\\lumia822.dtb", &dtb, &dtbSize);
    if (EFI_ERROR(s)) { SayHex(c, u"dtb read failed ", s); return s; }
    s = BS->InstallConfigurationTable(&DeviceTreeGuid, dtb);
    SayHex(c, u"[4] dtb installed, status ", s);

    INITRD_LOADER *initrd = NULL;
    void *initrdData = NULL; UINTN initrdSize = 0;
    if (!EFI_ERROR(ReadFile(c, root, u"\\linux\\initramfs.gz", &initrdData, &initrdSize)) &&
        !EFI_ERROR(BS->AllocatePool(2, sizeof(*initrd), (void **)&initrd))) {
        initrd->LoadFile = InitrdLoadFile;
        initrd->Data = initrdData;
        initrd->Size = initrdSize;
        EFI_HANDLE h = NULL;
        s = BS->InstallMultipleProtocolInterfaces(&h, &DevicePathGuid, &InitrdDevicePath, &LoadFile2Guid, initrd, NULL);
        SayHex(c, u"[5] initrd size ", initrdSize);
        SayHex(c, u"    initrd protocol status ", s);
    } else Say(c, u"[5] no initramfs\r\n");

    // Command line: \linux\cmdline.txt (ASCII) if present
    CHAR16 *cmd = NULL;
    if (EFI_ERROR(BS->AllocatePool(2, 512 * sizeof(CHAR16), (void **)&cmd))) return EFI_NOT_FOUND;
    void *txt = NULL; UINTN txtSize = 0; const char *src = DefaultCmdline; UINTN n = 0;
    if (!EFI_ERROR(ReadFile(c, root, u"\\linux\\cmdline.txt", &txt, &txtSize))) { ((char *)txt)[txtSize] = 0; src = txt; }
    while (src[n] && src[n] != '\r' && src[n] != '\n' && n < 510) { cmd[n] = (CHAR16)src[n]; n++; }
    cmd[n] = 0;
    Say(c, u"[6] cmdline: "); Say(c, cmd); Say(c, u"\r\n");

    EFI_HANDLE kh = NULL;
    s = BS->LoadImage(0, ImageHandle, NULL, kernel, kernelSize, &kh);
    SayHex(c, u"[7] LoadImage status ", s);
    if (EFI_ERROR(s)) return s;
    EFI_LOADED_IMAGE *li = NULL;
    BS->HandleProtocol(kh, &LoadedImageGuid, (void **)&li);
    li->LoadOptions = cmd;
    li->LoadOptionsSize = (uint32_t)((n + 1) * sizeof(CHAR16));
    li->DeviceHandle = fsHandle;

    GOP *gop = NULL;
    s = BS->LocateProtocol(&GopGuid, NULL, (void **)&gop);
    if (!EFI_ERROR(s) && gop && gop->Mode && gop->Mode->Info) {
        SayHex(c, u"[7a] GOP framebuffer ", (uintptr_t)gop->Mode->FrameBufferBase);
        SayHex(c, u"     size ", gop->Mode->FrameBufferSize);
        SayHex(c, u"     width ", gop->Mode->Info->HorizontalResolution);
        SayHex(c, u"     height ", gop->Mode->Info->VerticalResolution);
        SayHex(c, u"     stride ", gop->Mode->Info->PixelsPerScanLine);
        SayHex(c, u"     format ", gop->Mode->Info->PixelFormat);
    } else SayHex(c, u"[7a] no GOP, status ", s);

    // Low-RAM part of the memory map (where the ARM32 EFI stub decompresses the kernel):
    // one line per region: type start pages
    UINTN mapSize = 0, key, descSize = 0; uint32_t descVer;
    BS->GetMemoryMap(&mapSize, NULL, &key, &descSize, &descVer);
    uint8_t *map = NULL;
    mapSize += 4096;
    if (!EFI_ERROR(BS->AllocatePool(2, mapSize, (void **)&map)) &&
        !EFI_ERROR(BS->GetMemoryMap(&mapSize, map, &key, &descSize, &descVer))) {
        Say(c, u"[7b] memory map below 0x84000000 (type start pages):\r\n");
        for (UINTN off = 0; off + descSize <= mapSize; off += descSize) {
            uint32_t type = *(uint32_t *)(map + off);
            uint64_t start = *(uint64_t *)(map + off + 8), pages = *(uint64_t *)(map + off + 24);
            if (start >= 0x84000000ull) continue;
            CHAR16 line[48]; int k = 0;
            const char *hex = "0123456789abcdef";
            line[k++] = (CHAR16)hex[(type >> 4) & 15]; line[k++] = (CHAR16)hex[type & 15]; line[k++] = u' ';
            for (int sh = 28; sh >= 0; sh -= 4) line[k++] = (CHAR16)hex[(start >> sh) & 15];
            line[k++] = u' ';
            for (int sh = 20; sh >= 0; sh -= 4) line[k++] = (CHAR16)hex[(pages >> sh) & 15];
            line[k++] = u' '; line[k++] = u' '; line[k] = 0;
            c->ST->ConOut->OutputString(c->ST->ConOut, line);
        }
        Say(c, u"\r\n");
        BS->Stall(8 * 1000 * 1000);
    }

#ifdef HW_TEST
    // Hardware probe instead of booting: (1) paint the top third of the GOP framebuffer white
    // without a Blt, to see whether the panel scans that memory directly; (2) after 10 s drop
    // PS_HOLD (TLMM 0x00800820) to see whether that powers the phone off.
    if (gop && gop->Mode) {
        volatile uint32_t *fb = (volatile uint32_t *)(uintptr_t)gop->Mode->FrameBufferBase;
        for (UINTN i = 0; i < gop->Mode->FrameBufferSize / 4 / 3; i++) fb[i] = 0xFFFFFFFFu;
    }
    Say(c, u"[T1] framebuffer painted; PS_HOLD drop in 10 s\r\n");
    BS->Stall(10 * 1000 * 1000);
    *(volatile uint32_t *)0x00800820u = 0;
    BS->Stall(5 * 1000 * 1000);
    Say(c, u"[T2] still alive after PS_HOLD write\r\n");
    return EFI_SUCCESS;
#endif

    Say(c, u"[8] starting kernel...\r\n");
    BS->Stall(2 * 1000 * 1000);
    s = BS->StartImage(kh, NULL, NULL);
    SayHex(c, u"[9] StartImage returned ", s);
    return s;
}

// ---------------------------------------------------------------------------------------------
// Boot manager application entry: same context switch as BootShim's SwitchToRealModeContext
typedef struct {
    uint32_t Version, Unknown;
    EFI_HANDLE ImageHandle;
    EFI_SYSTEM_TABLE *SystemTable;
    uint32_t Control, Vbar, Reserved, Reserved2, IdSvcRW;     // ARM_EXCEPTION_STATE
    char MpExtensions;                                        // ARM_MM_STATE
    uint32_t HardwarePageDirectory, TTB_Config, SoftwarePageDirectory, MappedHardwarePageDirectory;
    uint32_t InterruptState;
} BL_FIRMWARE_DESCRIPTOR;

#define MCR(v, crn, op1, crm, op2) __asm__ volatile("mcr p15, " #op1 ", %0, c" #crn ", c" #crm ", " #op2 :: "r"(v) : "memory")
#define DSB() __asm__ volatile("dsb sy" ::: "memory")
#define ISB() __asm__ volatile("isb sy" ::: "memory")

int BlApplicationEntry(uint8_t *Params, void *LibraryParams)
{
    if (!Params) return (int)0xC000000D; // STATUS_INVALID_PARAMETER
    BL_FIRMWARE_DESCRIPTOR *fd = (BL_FIRMWARE_DESCRIPTOR *)(Params + *(volatile uint32_t *)(Params + 48));

    __asm__ volatile("cpsid i" ::: "memory");
    MCR(fd->HardwarePageDirectory | fd->TTB_Config, 2, 0, 0, 0);   // TTBR0
    ISB();
    MCR(0, 8, 0, 7, 0);                                             // TLBIALL
    MCR(0, 7, 0, 5, 6);                                             // BPIALL
    DSB(); ISB();
    MCR(fd->IdSvcRW, 13, 0, 0, 4);                                  // TPIDRPRW
    DSB();
    MCR(fd->Control, 1, 0, 0, 0);                                   // SCTLR
    MCR(0, 7, 0, 5, 6);
    DSB(); ISB();
    MCR(fd->Vbar, 12, 0, 0, 0);                                     // VBAR
    ISB();
    if (fd->InterruptState) __asm__ volatile("cpsie i" ::: "memory");

    if (fd->SystemTable) {
        // Without this first console write + 3 s stall straight after the context switch the
        // loader hangs silently on this firmware (found by bisecting with canaries C2/C4).
        static const uint16_t hello[] = u"\r\n\r\n   LinuxLoader starting\r\n";
        uint8_t *st = (uint8_t *)fd->SystemTable;
        SIMPLE_TEXT_OUTPUT *out = *(SIMPLE_TEXT_OUTPUT **)(st + 0x2c);
        out->OutputString(out, hello);
        (*(EFI_STATUS (**)(UINTN))(*(uint8_t **)(st + 0x3c) + 136))(3u * 1000u * 1000u);
        efi_main(fd->ImageHandle, fd->SystemTable);
        fd->SystemTable->BootServices->Stall(20 * 1000 * 1000);  // leave messages visible on failure
    }
    return 0;
}
