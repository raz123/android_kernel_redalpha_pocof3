FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bc bison build-essential ca-certificates clang curl flex \
    gcc-aarch64-linux-gnu git \
    libelf-dev libncurses-dev libssl-dev lld llvm lz4 python3 rsync zip \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
CMD ["/bin/bash"]
