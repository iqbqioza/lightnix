# Debian 13 slim: validated base image (amd64).
FROM docker.io/library/debian:13-slim@sha256:1e1a22175fbf1b32157ddaf0219e1db4e5401fab2b94ed285add64d18587cd2d

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash binutils bison build-essential bzip2 ca-certificates coreutils \
    diffutils file findutils gawk grep gzip m4 patch perl python3 sed \
    tar texinfo xz-utils wget && \
    ln -sf bash /bin/sh && \
    rm -rf /var/lib/apt/lists/*

ENV LC_ALL=POSIX
WORKDIR /work
CMD ["/bin/bash"]
