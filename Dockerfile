FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bc bison build-essential ca-certificates curl flex gnupg2 \
    gcc-aarch64-linux-gnu git lcov \
    libelf-dev libncurses-dev libssl-dev lz4 ninja-build \
    python3 python3-pip python3-pyelftools rsync unzip zip \
    && apt-get install -y wget software-properties-common \
    && wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - \
    && echo "deb http://apt.llvm.org/jammy/ llvm-toolchain-jammy-17 main" > /etc/apt/sources.list.d/llvm-17.list \
    && apt-get update \
    && apt-get install -y clang-17 clang-format-17 clang-tidy-17 lld-17 llvm-17 \
    && ln -sf /usr/bin/clang-17 /usr/bin/clang \
    && ln -sf /usr/bin/ld.lld-17 /usr/bin/ld.lld \
    && ln -sf /usr/bin/lld-17 /usr/bin/lld \
    && ln -sf /usr/bin/llvm-ar-17 /usr/bin/llvm-ar \
    && ln -sf /usr/bin/llvm-nm-17 /usr/bin/llvm-nm \
    && ln -sf /usr/bin/llvm-objcopy-17 /usr/bin/llvm-objcopy \
    && ln -sf /usr/bin/llvm-objdump-17 /usr/bin/llvm-objdump \
    && ln -sf /usr/bin/llvm-strip-17 /usr/bin/llvm-strip \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
CMD ["/bin/bash"]
