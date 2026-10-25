// regdump <base-hex> <offset-hex>... : print 32-bit registers via /dev/mem
// regdump -w <addr-hex> <value-hex>  : write one 32-bit register
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static volatile uint32_t *map(int fd, unsigned long addr, unsigned long *page)
{
    *page = addr & ~0xfffUL;
    void *p = mmap(NULL, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)*page);
    if (p == MAP_FAILED) { printf("mmap %#lx: %s\n", *page, strerror(errno)); exit(1); }
    return (volatile uint32_t *)((char *)p + (addr - *page));
}

int main(int argc, char **argv)
{
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { printf("open /dev/mem: %s\n", strerror(errno)); return 1; }
    unsigned long page;
    if (argc == 4 && !strcmp(argv[1], "-w")) {
        unsigned long a = strtoul(argv[2], 0, 16);
        volatile uint32_t *r = map(fd, a, &page);
        *r = (uint32_t)strtoul(argv[3], 0, 16);
        printf("%#lx <= %#010x (now %#010x)\n", a, (unsigned)strtoul(argv[3], 0, 16), *r);
        return 0;
    }
    unsigned long base = strtoul(argv[1], 0, 16);
    for (int i = 2; i < argc; i++) {
        unsigned long a = base + strtoul(argv[i], 0, 16);
        volatile uint32_t *r = map(fd, a, &page);
        printf("%s=%08x ", argv[i], *r);
        munmap((void *)((uintptr_t)r & ~0xfffUL), 0x1000);
    }
    printf("\n");
    return 0;
}
