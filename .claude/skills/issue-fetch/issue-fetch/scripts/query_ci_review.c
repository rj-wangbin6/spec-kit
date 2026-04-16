/**
 * Issue Fetch 查询工具
 *
 * 功能：通过 changeNumber 查询锐捷 CI 平台的 Coverity 问题详情
 *
 * 编译（Windows / MinGW）:
 *   gcc -o query_ci_review.exe query_ci_review.c -lwinhttp -lws2_32 -O2
 *
 * 编译（macOS / Linux）:
 *   gcc -o query_ci_review query_ci_review.c -lcurl -O2
 *
 * 使用：query_ci_review[.exe] [--json] <changeNumber>
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define API_BASE_URL  "http://rgci.ruijie.com.cn/rgci/report/outside/api/gerrity/gerrityCoverity/getPageData"
#define MAX_URL_LENGTH    512
#define MAX_RESPONSE_SIZE 1048576  /* 1MB */

/* ================================================================
 * Windows 实现：使用系统内置 WinHTTP，无需第三方库
 * ================================================================ */
#ifdef _WIN32

#include <windows.h>
#include <winhttp.h>

#pragma comment(lib, "winhttp.lib")

int query_ci_review(const char *change_number, int json_only) {
    HINTERNET hSession = NULL, hConnect = NULL, hRequest = NULL;
    WCHAR wPath[MAX_URL_LENGTH];
    char *response = NULL;
    DWORD responseSize = 0;
    DWORD bytesRead = 0;
    DWORD statusCode = 0;
    DWORD statusCodeSize = sizeof(statusCode);
    char buf[4096];
    int ret = 0;

    _snwprintf(wPath, MAX_URL_LENGTH,
               L"/rgci/report/outside/api/gerrity/gerrityCoverity/getPageData?changeNumber=%S",
               change_number);

    if (!json_only) {
        printf("正在查询 changeNumber: %s\n", change_number);
        printf("请求URL: %s?changeNumber=%s\n\n", API_BASE_URL, change_number);
    }

    hSession = WinHttpOpen(L"IssueFetch/1.0",
                           WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                           WINHTTP_NO_PROXY_NAME,
                           WINHTTP_NO_PROXY_BYPASS, 0);
    if (!hSession) {
        fprintf(stderr, "错误: WinHTTP 初始化失败 (code=%lu)\n", GetLastError());
        return -1;
    }

    WinHttpSetTimeouts(hSession, 30000, 30000, 30000, 30000);

    hConnect = WinHttpConnect(hSession, L"rgci.ruijie.com.cn", 80, 0);
    if (!hConnect) {
        fprintf(stderr, "错误: 连接服务器失败 (code=%lu)\n", GetLastError());
        ret = -1; goto cleanup;
    }

    hRequest = WinHttpOpenRequest(hConnect, L"GET", wPath,
                                  NULL, WINHTTP_NO_REFERER,
                                  WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
    if (!hRequest) {
        fprintf(stderr, "错误: 创建请求失败 (code=%lu)\n", GetLastError());
        ret = -1; goto cleanup;
    }

    if (!WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            WINHTTP_NO_REQUEST_DATA, 0, 0, 0)) {
        fprintf(stderr, "错误: 请求失败 (code=%lu)\n", GetLastError());
        ret = -1; goto cleanup;
    }

    if (!WinHttpReceiveResponse(hRequest, NULL)) {
        fprintf(stderr, "错误: 接收响应失败 (code=%lu)\n", GetLastError());
        ret = -1; goto cleanup;
    }

    WinHttpQueryHeaders(hRequest,
                        WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX,
                        &statusCode, &statusCodeSize, WINHTTP_NO_HEADER_INDEX);

    response = (char *)malloc(1);
    response[0] = '\0';
    responseSize = 0;

    while (1) {
        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(hRequest, &available) || available == 0) break;
        if (available > sizeof(buf) - 1) available = sizeof(buf) - 1;
        if (!WinHttpReadData(hRequest, buf, available, &bytesRead) || bytesRead == 0) break;
        if (responseSize + bytesRead >= MAX_RESPONSE_SIZE) {
            fprintf(stderr, "错误: 响应数据过大\n");
            ret = -1; goto cleanup;
        }
        char *tmp = (char *)realloc(response, responseSize + bytesRead + 1);
        if (!tmp) { fprintf(stderr, "错误: 内存分配失败\n"); ret = -1; goto cleanup; }
        response = tmp;
        memcpy(response + responseSize, buf, bytesRead);
        responseSize += bytesRead;
        response[responseSize] = '\0';
    }

    if (json_only) {
        printf("%s\n", response);
    } else {
        printf("HTTP状态码: %lu\n", statusCode);
        printf("==================== 响应内容 ====================\n");
        printf("%s\n", response);
        printf("================================================\n");
    }

    if (statusCode != 200) { fprintf(stderr, "警告: HTTP状态码异常\n"); ret = -1; }

cleanup:
    if (response)  free(response);
    if (hRequest)  WinHttpCloseHandle(hRequest);
    if (hConnect)  WinHttpCloseHandle(hConnect);
    if (hSession)  WinHttpCloseHandle(hSession);
    return ret;
}

/* ================================================================
 * macOS / Linux 实现：使用 libcurl
 * ================================================================ */
#else

#include <curl/curl.h>

typedef struct {
    char  *data;
    size_t size;
} ResponseData;

static size_t write_callback(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t realsize = size * nmemb;
    ResponseData *mem = (ResponseData *)userp;

    if (mem->size + realsize > MAX_RESPONSE_SIZE) {
        fprintf(stderr, "错误: 响应数据过大\n");
        return 0;
    }

    char *ptr = realloc(mem->data, mem->size + realsize + 1);
    if (ptr == NULL) { fprintf(stderr, "错误: 内存分配失败\n"); return 0; }

    mem->data = ptr;
    memcpy(&(mem->data[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->data[mem->size] = 0;
    return realsize;
}

int query_ci_review(const char *change_number, int json_only) {
    CURL *curl;
    CURLcode res;
    char url[MAX_URL_LENGTH];
    ResponseData response;
    int ret = 0;

    response.data = malloc(1);
    response.size = 0;
    if (response.data == NULL) { fprintf(stderr, "错误: 内存分配失败\n"); return -1; }

    snprintf(url, MAX_URL_LENGTH, "%s?changeNumber=%s", API_BASE_URL, change_number);

    if (!json_only) {
        printf("正在查询 changeNumber: %s\n", change_number);
        printf("请求URL: %s\n\n", url);
    }

    curl_global_init(CURL_GLOBAL_DEFAULT);
    curl = curl_easy_init();

    if (curl) {
        curl_easy_setopt(curl, CURLOPT_URL, url);
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&response);
        curl_easy_setopt(curl, CURLOPT_USERAGENT, "IssueFetch/1.0");

        res = curl_easy_perform(curl);

        if (res != CURLE_OK) {
            fprintf(stderr, "错误: 请求失败 - %s\n", curl_easy_strerror(res));
            ret = -1;
        } else {
            long response_code;
            curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);

            if (json_only) {
                printf("%s\n", response.data);
            } else {
                printf("HTTP状态码: %ld\n", response_code);
                printf("==================== 响应内容 ====================\n");
                printf("%s\n", response.data);
                printf("================================================\n");
            }

            if (response_code != 200) { fprintf(stderr, "警告: HTTP状态码异常\n"); ret = -1; }
        }

        curl_easy_cleanup(curl);
    } else {
        fprintf(stderr, "错误: CURL初始化失败\n");
        ret = -1;
    }

    curl_global_cleanup();
    free(response.data);
    return ret;
}

#endif  /* _WIN32 */

/**
 * 显示使用帮助
 */
void show_usage(const char *program_name) {
    printf("Issue Fetch 查询工具\n\n");
    printf("用法:\n");
    printf("  %s <changeNumber>\n", program_name);
    printf("  %s --json <changeNumber>\n\n", program_name);
    printf("参数:\n");
    printf("  changeNumber    Gerrit变更编号（必需）\n");
    printf("  --json, -j      仅输出 JSON 响应体，便于脚本和 CI 直接消费\n\n");
    printf("示例:\n");
    printf("  %s 777918\n", program_name);
    printf("  %s --json 777918\n\n", program_name);
    printf("说明:\n");
    printf("  查询指定 changeNumber 的 Coverity 代码检查结果\n");
    printf("  默认输出查询日志和 JSON 响应体；使用 --json 可只输出 JSON\n\n");
}

/**
 * 验证changeNumber格式
 */
int validate_change_number(const char *change_number) {
    if (change_number == NULL || strlen(change_number) == 0) {
        return 0;
    }

    // 检查是否全为数字
    for (size_t i = 0; i < strlen(change_number); i++) {
        if (change_number[i] < '0' || change_number[i] > '9') {
            return 0;
        }
    }

    return 1;
}

/**
 * 主函数
 */
int main(int argc, char *argv[]) {
    int json_only = 0;
    const char *change_number = NULL;

    // 设置Windows控制台UTF-8编码支持
    #ifdef _WIN32
    system("chcp 65001 > nul");
    #endif

    // 检查参数数量
    if (argc < 2) {
        show_usage(argv[0]);
        return 1;
    }

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            show_usage(argv[0]);
            return 0;
        }

        if (strcmp(argv[i], "--json") == 0 || strcmp(argv[i], "-j") == 0) {
            json_only = 1;
            continue;
        }

        if (argv[i][0] == '-') {
            fprintf(stderr, "错误: 未知参数 %s\n", argv[i]);
            fprintf(stderr, "提示: 使用 --help 查看使用说明\n");
            return 1;
        }

        if (change_number != NULL) {
            fprintf(stderr, "错误: 提供了多个 changeNumber 参数\n");
            fprintf(stderr, "提示: 使用 --help 查看使用说明\n");
            return 1;
        }

        change_number = argv[i];
    }

    if (change_number == NULL) {
        show_usage(argv[0]);
        return 1;
    }

    // 验证changeNumber格式
    if (!validate_change_number(change_number)) {
        fprintf(stderr, "错误: changeNumber格式无效，必须是纯数字\n");
        fprintf(stderr, "提示: 使用 --help 查看使用说明\n");
        return 1;
    }

    // 执行查询
    int result = query_ci_review(change_number, json_only);

    if (result == 0) {
        if (!json_only) {
            printf("\n查询完成！\n");
        }
        return 0;
    } else {
        if (!json_only) {
            fprintf(stderr, "\n查询失败！\n");
        }
        return 1;
    }
}
