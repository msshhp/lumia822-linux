// recv: receive one file over TCP and write it to disk (Windows 10 Mobile, ARM32).
//   recv <port> <outfile>
// Protocol: client connects, sends a 4-byte little-endian length, then the bytes. recv replies
// "OK <bytes>\n" (or "ERR\n") and exits.
#include <winsock2.h>
#include <windows.h>

static unsigned parseu(const wchar_t *s) { unsigned v = 0; while (*s >= L'0' && *s <= L'9') v = v * 10 + (*s++ - L'0'); return v; }

static int recvall(SOCKET s, char *buf, int len)
{
    int got = 0;
    while (got < len) { int n = recv(s, buf + got, len - got, 0); if (n <= 0) return -1; got += n; }
    return got;
}

void mainCRTStartup(void)
{
    wchar_t *cl = GetCommandLineW(), *argv[4]; int argc = 0;
    while (*cl && argc < 4) {
        while (*cl == L' ') cl++;
        if (!*cl) break;
        argv[argc++] = cl;
        while (*cl && *cl != L' ') cl++;
        if (*cl) *cl++ = 0;
    }
    if (argc < 3) ExitProcess(2);

    WSADATA wsa; WSAStartup(MAKEWORD(2, 2), &wsa);
    SOCKET ls = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET; a.sin_port = htons((unsigned short)parseu(argv[1])); a.sin_addr.s_addr = INADDR_ANY;
    if (bind(ls, (struct sockaddr *)&a, sizeof(a)) || listen(ls, 1)) ExitProcess(3);
    SOCKET s = accept(ls, NULL, NULL);
    unsigned len = 0;
    char *buf = NULL;
    int ok = recvall(s, (char *)&len, 4) == 4 && (buf = (char *)VirtualAlloc(NULL, len + 1, MEM_COMMIT, PAGE_READWRITE)) && recvall(s, buf, (int)len) == (int)len;
    if (ok) {
        HANDLE f = CreateFileW(argv[2], GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
        DWORD w = 0;
        ok = f != INVALID_HANDLE_VALUE && WriteFile(f, buf, len, &w, NULL) && w == len;
        if (f != INVALID_HANDLE_VALUE) CloseHandle(f);
    }
    char msg[32]; int m = 0;
    if (ok) {
        char d[12]; int k = 0; unsigned v = len;
        do { d[k++] = (char)('0' + v % 10); v /= 10; } while (v);
        msg[m++] = 'O'; msg[m++] = 'K'; msg[m++] = ' ';
        while (k) msg[m++] = d[--k];
    } else { msg[m++] = 'E'; msg[m++] = 'R'; msg[m++] = 'R'; }
    msg[m++] = '\n';
    send(s, msg, m, 0);
    closesocket(s); closesocket(ls);
    ExitProcess(ok ? 0 : 1);
}
