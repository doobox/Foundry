#include "FoundryCurlBridge.h"

#include <curl/curl.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    const uint8_t *bytes;
    size_t length;
    size_t offset;
    FoundryCurlProgressCallback progress;
    void *progressContext;
} FoundryCurlContext;

static size_t FoundryCurlRead(char *buffer, size_t size, size_t count, void *contextPointer) {
    FoundryCurlContext *context = contextPointer;
    size_t capacity = size * count;
    size_t remaining = context->length - context->offset;
    size_t copied = remaining < capacity ? remaining : capacity;
    if (copied > 0) {
        memcpy(buffer, context->bytes + context->offset, copied);
        context->offset += copied;
    }
    return copied;
}

static size_t FoundryCurlDiscard(char *buffer, size_t size, size_t count, void *context) {
    (void)buffer;
    (void)context;
    return size * count;
}

static int FoundryCurlProgress(
    void *contextPointer,
    curl_off_t downloadTotal,
    curl_off_t downloadNow,
    curl_off_t uploadTotal,
    curl_off_t uploadNow
) {
    (void)downloadTotal;
    (void)downloadNow;
    FoundryCurlContext *context = contextPointer;
    if (context->progress == NULL) {
        return 0;
    }
    return context->progress((int64_t)uploadNow, (int64_t)uploadTotal, context->progressContext);
}

static void FoundryCurlInitialize(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        curl_global_init(CURL_GLOBAL_DEFAULT);
    });
}

static void FoundryCurlCopyError(char *destination, size_t length, const char *message) {
    if (destination == NULL || length == 0) {
        return;
    }
    snprintf(destination, length, "%s", message == NULL ? "Publishing failed." : message);
}

int32_t FoundryCurlPerform(
    const FoundryCurlRequest *request,
    FoundryCurlProgressCallback progress,
    void *contextPointer,
    char *errorMessage,
    size_t errorMessageLength
) {
    if (request == NULL || request->url == NULL) {
        FoundryCurlCopyError(errorMessage, errorMessageLength, "The publishing URL is missing.");
        return (int32_t)CURLE_URL_MALFORMAT;
    }

    FoundryCurlInitialize();
    CURL *curl = curl_easy_init();
    if (curl == NULL) {
        FoundryCurlCopyError(errorMessage, errorMessageLength, "Unable to initialise the publishing connection.");
        return (int32_t)CURLE_FAILED_INIT;
    }

    char curlError[CURL_ERROR_SIZE] = {0};
    FoundryCurlContext context = {
        .bytes = request->data,
        .length = request->dataLength,
        .offset = 0,
        .progress = progress,
        .progressContext = contextPointer
    };

    curl_easy_setopt(curl, CURLOPT_URL, request->url);
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, curlError);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 20L);
    curl_easy_setopt(curl, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt(curl, CURLOPT_LOW_SPEED_TIME, 60L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, FoundryCurlDiscard);

    if (request->username != NULL) {
        curl_easy_setopt(curl, CURLOPT_USERNAME, request->username);
    }
    if (request->password != NULL) {
        curl_easy_setopt(curl, CURLOPT_PASSWORD, request->password);
    }
    if (request->caCertificatePath != NULL) {
        curl_easy_setopt(curl, CURLOPT_CAINFO, request->caCertificatePath);
    }
    if (request->knownHostsPath != NULL) {
        curl_easy_setopt(curl, CURLOPT_SSH_KNOWNHOSTS, request->knownHostsPath);
    }
    if (request->awsSignature != NULL) {
        curl_easy_setopt(curl, CURLOPT_AWS_SIGV4, request->awsSignature);
    }
    if (request->requireExplicitFTPSTLS != 0) {
        curl_easy_setopt(curl, CURLOPT_USE_SSL, (long)CURLUSESSL_ALL);
    }
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, FoundryCurlProgress);
    curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &context);

    struct curl_slist *commands = NULL;
    if (request->deleteOnly != 0) {
        if (request->awsSignature != NULL) {
            curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "DELETE");
        } else if (request->deleteCommand != NULL) {
            commands = curl_slist_append(commands, request->deleteCommand);
            curl_easy_setopt(curl, CURLOPT_QUOTE, commands);
            curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
        }
    } else if (request->testOnly != 0) {
        if (request->awsSignature != NULL) {
            curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
        } else {
            curl_easy_setopt(curl, CURLOPT_DIRLISTONLY, 1L);
        }
    } else {
        curl_easy_setopt(curl, CURLOPT_UPLOAD, 1L);
        curl_easy_setopt(curl, CURLOPT_READFUNCTION, FoundryCurlRead);
        curl_easy_setopt(curl, CURLOPT_READDATA, &context);
        curl_easy_setopt(curl, CURLOPT_INFILESIZE_LARGE, (curl_off_t)request->dataLength);
        curl_easy_setopt(curl, CURLOPT_FTP_CREATE_MISSING_DIRS,
                         request->createRemoteDirectories != 0 ? (long)CURLFTP_CREATE_DIR_RETRY : 0L);
    }

    CURLcode result = curl_easy_perform(curl);
    if (result != CURLE_OK) {
        const char *message = curlError[0] == '\0' ? curl_easy_strerror(result) : curlError;
        FoundryCurlCopyError(errorMessage, errorMessageLength, message);
    }
    curl_slist_free_all(commands);
    curl_easy_cleanup(curl);
    return (int32_t)result;
}

const char *FoundryCurlVersion(void) {
    FoundryCurlInitialize();
    return curl_version();
}
