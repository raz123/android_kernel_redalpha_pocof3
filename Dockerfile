FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bc bison build-essential ca-certificates curl flex \
    gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi git \
    libelf-dev libncurses-dev libssl-dev lz4 python3 \
    rsync unzip wget zip \
    && rm -rf /var/lib/apt/lists/*

# Install ZyC-Clang 16 (same as AstideLabs)
RUN mkdir -p /opt/zyc-clang && cd /opt/zyc-clang \
    && wget -q https://github.com/ZyCromerZ/Clang/releases/download/16.0.6-20260510-release/Clang-16.0.6-20260510.tar.gz \
    && tar -zxf Clang-16.0.6-20260510.tar.gz \
    && rm Clang-16.0.6-20260510.tar.gz \
    && ln -sf /opt/zyc-clang/bin/clang /usr/local/bin/clang \
    && ln -sf /opt/zyc-clang/bin/ld.lld /usr/local/bin/ld.lld \
    && ln -sf /opt/zyc-clang/bin/lld /usr/local/bin/lld \
    && ln -sf /opt/zyc-clang/bin/llvm-ar /usr/local/bin/llvm-ar \
    && ln -sf /opt/zyc-clang/bin/llvm-nm /usr/local/bin/llvm-nm \
    && ln -sf /opt/zyc-clang/bin/llvm-objcopy /usr/local/bin/llvm-objcopy \
    && ln -sf /opt/zyc-clang/bin/llvm-objdump /usr/local/bin/llvm-objdump \
    && ln -sf /opt/zyc-clang/bin/llvm-strip /usr/local/bin/llvm-strip

ENV PATH="/opt/zyc-clang/bin:${PATH}"
WORKDIR /workspace
CMD ["/bin/bash"]
