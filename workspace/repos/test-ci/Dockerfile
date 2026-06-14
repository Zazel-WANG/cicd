FROM ubuntu:22.04

# 换阿里云源（加速）
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    apt update && \
    apt install -y --no-install-recommends \
        gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu \
        make \
        cmake \
        file \
    && rm -rf /var/lib/apt/lists/*

# 设默认编译器为 ARM64 交叉编译器
ENV CC=aarch64-linux-gnu-gcc
ENV CXX=aarch64-linux-gnu-g++
ENV ARCH=arm64
