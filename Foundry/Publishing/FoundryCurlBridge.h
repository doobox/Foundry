#ifndef FoundryCurlBridge_h
#define FoundryCurlBridge_h

#include <stddef.h>
#include <stdint.h>

typedef int32_t (*FoundryCurlProgressCallback)(
    int64_t uploadedBytes,
    int64_t totalBytes,
    void *context
);

typedef struct {
    const char *url;
    const char *username;
    const char *password;
    const char *caCertificatePath;
    const char *knownHostsPath;
    const char *awsSignature;
    const uint8_t *data;
    size_t dataLength;
    int32_t testOnly;
    int32_t deleteOnly;
    const char *deleteCommand;
    int32_t createRemoteDirectories;
    int32_t requireExplicitFTPSTLS;
} FoundryCurlRequest;

int32_t FoundryCurlPerform(
    const FoundryCurlRequest *request,
    FoundryCurlProgressCallback progress,
    void *context,
    char *errorMessage,
    size_t errorMessageLength
);

const char *FoundryCurlVersion(void);

#endif
