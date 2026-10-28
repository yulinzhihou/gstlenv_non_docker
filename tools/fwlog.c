/*
 * fwlog.c — GS游享网·天龙八部万能环境 武道四 v3 兼容层
 *
 * 用途: 武道四 v3 Server1 存在日志栈缓冲溢出缺陷(日志分隔线写入固定栈缓冲溢出,
 *       导致 fwrite 第4参数 FILE* 被破坏为 NULL 后 SIGSEGV)。
 *       本包装器拦截 fwrite: 当 stream==NULL 时直接返回 0(不崩溃),
 *       并可选输出每次 fwrite 的日志内容供端作者定位。
 *
 * 编译: gcc -shared -fPIC -O0 -o fwlog.so fwlog.c -ldl
 * 使用: LD_PRELOAD=/opt/fwlog.so ./Server1
 *       (配合 export LD_LIBRARY_PATH=/home/tlbb/tlbb1/Server)
 *
 * 说明: 此为端作者修复二进制前的部分缓解, 可将 Server1 初始化推进 20+ Manager,
 *       但无法完全规避栈破坏。修复方向见 docs/武道四v3兼容层.md
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <dlfcn.h>
#include <unistd.h>
#include <fcntl.h>

static int fd = -1;

/* 可选: 1=记录每次 fwrite 到 /tmp/fwlog.txt(诊断用, 默认关闭避免膨胀) */
#define FWLOG_VERBOSE 0

size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    static size_t (*real)(const void*, size_t, size_t, FILE*) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "fwrite");

#if FWLOG_VERBOSE
    if (fd < 0) fd = open("/tmp/fwlog.txt", O_WRONLY|O_CREAT|O_APPEND, 0644);
    if (fd >= 0) {
        size_t n = size*nmemb;
        char hdr[128];
        int hl = snprintf(hdr, sizeof(hdr), "fwrite n=%zu stream=%p\n", n, stream);
        write(fd, hdr, hl);
        size_t w = n > 512 ? 512 : n;
        if (ptr && w) write(fd, ptr, w);
        write(fd, "\n---\n", 5);
    }
#endif

    /* 核心缓解: NULL stream 直接丢弃(返回 0), 避免 fwrite 内部解引用崩溃 */
    if (!stream) return 0;
    return real(ptr, size, nmemb, stream);
}
