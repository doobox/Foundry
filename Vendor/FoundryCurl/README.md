# FoundryCurl

Foundry ships its own arm64 build of libcurl so publishing does not depend on
Homebrew or command-line tools installed on the customer's Mac.

The binary contains pinned builds of:

- curl 8.16.0
- libssh2 1.11.1
- mbedTLS 3.6.4

It targets macOS 27 and supports HTTP/HTTPS, FTP/FTPS, SCP/SFTP, AWS SigV4,
upload progress callbacks, and cancellation. Rebuild it with `build.sh` after
reviewing and updating the version constants and SHA-256 checksums.

Licences for the embedded projects are retained in `Licenses`.
