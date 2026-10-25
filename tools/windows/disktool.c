// disktool: minimal raw-disk reader for Windows 10 Mobile (ARM32), kernel32 only.
//   disktool gpt [drive#]                  - print GPT partitions
//   disktool read <drive#> <lba> <count> <outfile> - dump sectors to a file
#include <windows.h>

static HANDLE hOut;

static void out(const char *s) { DWORD n; WriteFile(hOut, s, lstrlenA(s), &n, NULL); }

static void outu(unsigned long long v) {
    char b[24]; int i = 23; b[i] = 0;
    do { b[--i] = '0' + (char)(v % 10); v /= 10; } while (v);
    out(b + i);
}

static void outhex(const unsigned char *p, int n) {
    static const char h[] = "0123456789abcdef"; char b[3]; b[2] = 0;
    for (int i = 0; i < n; i++) { b[0] = h[p[i] >> 4]; b[1] = h[p[i] & 15]; out(b); }
}

static unsigned long long parseu(const wchar_t *s) {
    unsigned long long v = 0;
    while (*s >= L'0' && *s <= L'9') v = v * 10 + (*s++ - L'0');
    return v;
}

static HANDLE opendrive(int n) {
    wchar_t path[] = L"\\\\.\\PhysicalDrive0";
    path[17] = (wchar_t)(L'0' + n);
    return CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
}

static BOOL readlba(HANDLE h, unsigned long long lba, void *buf, DWORD bytes) {
    LARGE_INTEGER off; off.QuadPart = (LONGLONG)(lba * 512);
    DWORD n;
    if (!SetFilePointerEx(h, off, NULL, FILE_BEGIN)) return FALSE;
    return ReadFile(h, buf, bytes, &n, NULL) && n == bytes;
}

static void err(const char *what) { out(what); out(" failed, GetLastError="); outu(GetLastError()); out("\r\n"); }

static int cmd_gpt(int drive) {
    HANDLE h = opendrive(drive);
    if (h == INVALID_HANDLE_VALUE) { err("open"); return 1; }
    unsigned char *buf = (unsigned char *)VirtualAlloc(NULL, 34 * 512, MEM_COMMIT, PAGE_READWRITE);
    if (!readlba(h, 0, buf, 34 * 512)) { err("read"); return 1; }
    unsigned char *hdr = buf + 512;
    if (hdr[0] != 'E' || hdr[1] != 'F' || hdr[2] != 'I') { out("no GPT signature\r\n"); return 1; }
    unsigned int count = *(unsigned int *)(hdr + 80), esz = *(unsigned int *)(hdr + 84);
    unsigned long long elba = *(unsigned long long *)(hdr + 72);
    out("entries="); outu(count); out(" size="); outu(esz); out(" lba="); outu(elba); out("\r\n");
    for (unsigned int i = 0; i < count && (elba * 512 + (i + 1) * esz) <= 34 * 512; i++) {
        unsigned char *e = buf + elba * 512 + i * esz;
        unsigned long long first = *(unsigned long long *)(e + 32), last = *(unsigned long long *)(e + 40);
        if (!first && !last) continue;
        char name[37]; int k;
        for (k = 0; k < 36; k++) { wchar_t c = ((wchar_t *)(e + 56))[k]; name[k] = (char)(c < 128 ? c : '?'); if (!c) break; }
        name[k] = 0;
        outu(i); out(" "); out(name); out(" first="); outu(first); out(" last="); outu(last);
        out(" type="); outhex(e, 16); out(" attr="); outhex(e + 48, 8); out("\r\n");
    }
    CloseHandle(h);
    return 0;
}

static int cmd_read(int drive, unsigned long long lba, unsigned long long count, const wchar_t *outfile) {
    HANDLE h = opendrive(drive);
    if (h == INVALID_HANDLE_VALUE) { err("open"); return 1; }
    HANDLE o = CreateFileW(outfile, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
    if (o == INVALID_HANDLE_VALUE) { err("create output"); return 1; }
    unsigned char *buf = (unsigned char *)VirtualAlloc(NULL, 256 * 512, MEM_COMMIT, PAGE_READWRITE);
    while (count) {
        DWORD chunk = count > 256 ? 256 : (DWORD)count, n;
        if (!readlba(h, lba, buf, chunk * 512)) { err("read"); return 1; }
        WriteFile(o, buf, chunk * 512, &n, NULL);
        lba += chunk; count -= chunk;
    }
    CloseHandle(o); CloseHandle(h);
    out("ok\r\n");
    return 0;
}

// write <drive> <lba> <infile>: writes the file (padded to whole sectors with the disk's existing
// bytes) at lba, then reads it back and compares.
static int cmd_write(int drive, unsigned long long lba, const wchar_t *infile) {
    HANDLE in = CreateFileW(infile, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (in == INVALID_HANDLE_VALUE) { err("open input"); return 1; }
    DWORD size = GetFileSize(in, NULL), n;
    DWORD sectors = (size + 511) / 512, bytes = sectors * 512;
    unsigned char *data = (unsigned char *)VirtualAlloc(NULL, bytes, MEM_COMMIT, PAGE_READWRITE);
    unsigned char *check = (unsigned char *)VirtualAlloc(NULL, bytes, MEM_COMMIT, PAGE_READWRITE);
    HANDLE h = CreateFileW(L"\\\\.\\PhysicalDrive0", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_FLAG_NO_BUFFERING | FILE_FLAG_WRITE_THROUGH, NULL);
    if (drive != 0 || h == INVALID_HANDLE_VALUE) { err("open disk rw"); return 1; }
    if (!readlba(h, lba, data, bytes)) { err("pre-read"); return 1; }   // keep tail bytes of last sector
    if (!ReadFile(in, data, size, &n, NULL) || n != size) { err("read input"); return 1; }
    LARGE_INTEGER off; off.QuadPart = (LONGLONG)(lba * 512);
    if (!SetFilePointerEx(h, off, NULL, FILE_BEGIN) || !WriteFile(h, data, bytes, &n, NULL) || n != bytes) { err("write"); return 1; }
    FlushFileBuffers(h);
    if (!readlba(h, lba, check, bytes)) { err("read-back"); return 1; }
    for (DWORD i = 0; i < bytes; i++) if (check[i] != data[i]) { out("VERIFY MISMATCH at byte "); outu(i); out("\r\n"); return 3; }
    out("write ok, verified "); outu(sectors); out(" sectors at lba "); outu(lba); out("\r\n");
    CloseHandle(h); CloseHandle(in);
    return 0;
}

void mainCRTStartup(void) {
    hOut = GetStdHandle(STD_OUTPUT_HANDLE);
    // split command line into up to 8 args (no quoting support needed)
    wchar_t *cl = GetCommandLineW(), *argv[8]; int argc = 0;
    while (*cl && argc < 8) {
        while (*cl == L' ') cl++;
        if (!*cl) break;
        argv[argc++] = cl;
        while (*cl && *cl != L' ') cl++;
        if (*cl) *cl++ = 0;
    }
    int rc = 2;
    if (argc >= 2 && argv[1][0] == L'g') rc = cmd_gpt(argc >= 3 ? (int)parseu(argv[2]) : 0);
    else if (argc >= 6 && argv[1][0] == L'r') rc = cmd_read((int)parseu(argv[2]), parseu(argv[3]), parseu(argv[4]), argv[5]);
    else if (argc >= 5 && argv[1][0] == L'w') rc = cmd_write((int)parseu(argv[2]), parseu(argv[3]), argv[4]);
    else out("usage: disktool gpt [drive] | read <drive> <lba> <count> <outfile> | write <drive> <lba> <infile>\r\n");
    ExitProcess(rc);
}
