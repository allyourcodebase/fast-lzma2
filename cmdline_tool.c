#ifdef _WIN32
    #include <windows.h>
#else
    #include <errno.h>
    #include <unistd.h>
    #include <fcntl.h>
    #include <sys/mman.h>
#endif

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include <fast-lzma2.h>
#include <fl2_errors.h>

#define logf(fmt,...) do { fprintf(stderr, fmt "\n", ##__VA_ARGS__); fflush(stderr); } while (0)
#define errorf(fmt,...) do { fprintf(stderr, "error: " fmt "\n", ##__VA_ARGS__); fflush(stderr); } while (0)

typedef struct {
    unsigned char *ptr;
    size_t len;
#ifdef _WIN32
    HANDLE mapping;
#endif
}  MappedInFile;

MappedInFile mapInFile(const char *filename)
{
    MappedInFile map;

#ifdef _WIN32
    HANDLE handle = CreateFileA(
        filename,
        GENERIC_READ,
        FILE_SHARE_READ,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        NULL
    );
    if (INVALID_HANDLE_VALUE == handle) {
        errorf("open '%s' failed, error=%u", filename, GetLastError());
        ExitProcess(-1);
    }

    LARGE_INTEGER len_large = {0};
    if (!GetFileSizeEx(handle, &len_large)) {
        errorf("GetFileSize for '%s' failed, error=%u", filename, GetLastError());
        ExitProcess(-1);
    }
    logf("input file size is %llu bytes", (unsigned long long)len_large.QuadPart);
    map.len = (size_t)len_large.QuadPart;
    if (map.len != len_large.QuadPart) {
        errorf("file size is too large (%llu)", (unsigned long long)len_large.QuadPart);
        ExitProcess(-1);
    }

    map.mapping = CreateFileMappingA(
        handle,
        NULL,
        PAGE_READONLY,
        len_large.HighPart,
        len_large.LowPart,
        NULL
    );
    if (!map.mapping) {
        errorf("CreateFileMapping for '%s' failed, error=%u", filename, GetLastError());
        ExitProcess(-1);
    }
    map.ptr = (unsigned char*)MapViewOfFile(map.mapping, FILE_MAP_READ, 0, 0, map.len);
    if (!map.ptr) {
        errorf("MapViewOfFile for '%s' failed, error=%u", filename, GetLastError());
        ExitProcess(-1);
    }

    if (!CloseHandle(handle)) {
        errorf("CloseHandle for input file '%s' failed, error=%u", filename, GetLastError());
        ExitProcess(-1);
    }

#else
    int fd = open(filename, O_RDONLY);
    if (fd == -1) {
        errorf("open '%s' failed, errno=%d", filename, errno);
        exit(-1);
    }
    off_t len = lseek(fd, 0, SEEK_END);
    if (len == -1) {
        errorf("lseek to end of '%s' failed, errno=%d", filename, errno);
        exit(-1);
    }
    logf("input file size is %llu bytes", (unsigned long long)len);
    map.len = len;
    if (map.len != len) {
        errorf("input file size '%llu' is too big", (unsigned long long)len);
        exit(-1);
    }

    map.ptr = mmap(NULL, map.len, PROT_READ, MAP_PRIVATE, fd, 0);
    if (!map.ptr) {
        errorf("mmap of input file '%s' failed, errno=%d", filename, errno);
        exit(-1);
    }

    if (0 != close(fd)) {
        errorf("close '%s' failed, errno=%d", filename, errno);
        exit(-1);
    }
#endif
    return map;
}

typedef struct {
    unsigned char *ptr;
#ifdef _WIN32
    HANDLE mapping;
    HANDLE handle;
#else
    size_t len;
    int fd;
#endif
} MappedOutFile;

MappedOutFile mapOutFile(const char *filename, size_t len)
{
    MappedOutFile map;

#ifdef _WIN32
    LARGE_INTEGER len_large;
    len_large.QuadPart = (LONGLONG)len;
    if (len_large.QuadPart != len) {
        errorf("compress len (%llu) is too big", (unsigned long long)len);
        ExitProcess(-1);
    }

    map.handle = CreateFileA(
        filename,
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ,
        NULL,
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        NULL
    );
    if (INVALID_HANDLE_VALUE == map.handle) {
        errorf("failed to create '%s', error=%u", filename, GetLastError());
        ExitProcess(-1);
    }

    map.mapping = CreateFileMappingA(
        map.handle,
        NULL,
        PAGE_READWRITE,
        len_large.HighPart,
        len_large.LowPart,
        NULL
    );
    if (!map.mapping) {
        errorf("CreateFileMapping for '%s' failed, error=%u", filename, GetLastError());
        ExitProcess(-1);
    }

    map.ptr = (unsigned char*)MapViewOfFile(
        map.mapping,
        FILE_MAP_READ | FILE_MAP_WRITE,
        0,
        0,
        len
    );
    if (!map.ptr) {
        errorf("MapViewOfFile for '%s' failed, error=%u", filename, GetLastError());
        ExitProcess(-1);
    }

#else
    map.fd = open(filename, O_RDWR | O_CREAT, 0775);
    if (map.fd == -1) {
        errorf("create '%s' failed, errno=%d", filename, errno);
        exit(-1);
    }
    if (0 != ftruncate(map.fd, len)) {
        errorf("failed to truncate '%s', errno=%d", filename, errno);
        exit(-1);
    }
    map.ptr = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_SHARED, map.fd, 0);
    if (!map.ptr) {
        errorf("mmap of output file '%s' failed, errno=%d", filename, errno);
        exit(-1);
    }
    map.len = len;
#endif
    return map;
}

void finishOutFile(const char *filename, MappedOutFile map, size_t final_size)
{
#ifdef _WIN32
    LARGE_INTEGER final_size_large;
    final_size_large.QuadPart = final_size;
    if (final_size_large.QuadPart != final_size) {
        errorf("final compress length %llu is too large", (unsigned long long)final_size);
        ExitProcess(-1);
    }

    if (!UnmapViewOfFile(map.ptr)) {
        errorf("UnmapViewOfFile for '%s' failed, error=%u", filename, GetLastError());
        ExitProcess(-1);
    }
    if (!CloseHandle(map.mapping)) {
        errorf("CloseHandle for mapping of '%s' failed, error=%u", filename, GetLastError());
        ExitProcess(-1);
    }
    if (!SetFilePointerEx(map.handle, final_size_large, NULL, FILE_BEGIN)) {
        errorf("SetFilePointer for '%s' failed, error=%u", filename, GetLastError());
        ExitProcess(-1);
    }
    if (!SetEndOfFile(map.handle)) {
        errorf("SetEndOfFile for '%s' failed, error=%u", filename, GetLastError());
        ExitProcess(-1);
    }

    if (!CloseHandle(map.handle)) {
        errorf("CloseHandle for '%s' failed, error=%u", filename, GetLastError());
        ExitProcess(-1);
    }
#else
    if (0 != munmap(map.ptr, map.len)) {
        errorf("munmap of output file failed, errno=%d", errno);
        exit(-1);
    }
    if (0 != ftruncate(map.fd, final_size)) {
        errorf("failed to truncate '%s' to its final size, errno=%d", filename, errno);
        exit(-1);
    }
    if (0 != close(map.fd)) {
        errorf("close output file failed, errno=%d", filename, errno);
        exit(-1);
    }
#endif
}

int main(int argc, char **argv)
{
    if (argc <= 1) {
        fprintf(stderr, "Usage: tuplecompress compress|decompress IN_FILE OUT_FILE\n");
        fflush(stderr);
        return -1;
    }
    argc--; argv++;
    if (argc != 3) {
        errorf("expectd 3 cmdline arguments but got %d", argc);
        return -1;
    }
    const char *op_arg = argv[0];
    const char *in_filename = argv[1];
    const char *out_filename = argv[2];

    int decompress;
    if (0 == strcmp(op_arg, "compress")) {
        decompress = 0;
    } else if (0 == strcmp(op_arg, "decompress")) {
        decompress = 1;
    } else {
        errorf("expected cmdline op to be 'compress' or 'decompress' but got '%s'", op_arg);
        return -1;
    }

    MappedInFile in_map = mapInFile(in_filename);


    if (decompress) {
        unsigned long long decompress_buf_len = FL2_findDecompressedSize(in_map.ptr, in_map.len);
        if (decompress_buf_len == FL2_CONTENTSIZE_ERROR) {
            errorf("input file isn't lzma2 compressed");
            return -1;
        }
        logf("decompress len is %llu bytes", decompress_buf_len);

        MappedOutFile out_map = mapOutFile(out_filename, decompress_buf_len);
        size_t final_decompress_len = FL2_decompress(
            out_map.ptr,
            decompress_buf_len,
            in_map.ptr,
            in_map.len
        );
        {
            unsigned error_code = FL2_isError(final_decompress_len);
            if (error_code != 0) {
                const char *error_msg = FL2_getErrorString((FL2_ErrorCode)error_code);
                errorf("decompress failed, error=%d (%s)", error_code, error_msg);
                return -1;
            }
        }
        logf("final decompression size is %llu bytes", (unsigned long long)final_decompress_len);
        finishOutFile(out_filename, out_map, final_decompress_len);
        logf("Decompression successful");
    } else {
        size_t compress_buf_len = FL2_compressBound(in_map.len);
        logf("compress buffer len is %llu bytes", (unsigned long long)compress_buf_len);

        MappedOutFile out_map = mapOutFile(out_filename, compress_buf_len);
        size_t final_compress_len = FL2_compress(
            out_map.ptr,
            compress_buf_len,
            in_map.ptr,
            in_map.len,
            FL2_maxHighCLevel()
        );
        {
            unsigned error_code = FL2_isError(final_compress_len);
            if (error_code != 0) {
                const char *error_msg = FL2_getErrorString((FL2_ErrorCode)error_code);
                errorf("compress failed, error=%d (%s)", error_code, error_msg);
                return -1;
            }
        }
        logf("final compression size is %llu bytes", (unsigned long long)final_compress_len);
        finishOutFile(out_filename, out_map, final_compress_len);
        logf("Compression successful");
    }
    return 0;
}
