# LubanCat RK3588 OS 构建环境
# 用法: docker build -t os-builder:latest -f Dockerfile .
# Phase 2: 从本镜像启动容器, 挂载源码 volume, 执行 build.sh
FROM ubuntu:20.04

# 避免 tzdata 交互
ENV DEBIAN_FRONTEND=noninteractive

# 切阿里云镜像 (主机外网不通)
RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list && \
    sed -i 's|http://security.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list

# 构建依赖 (来自 LubanCat SDK README)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git ssh make gcc libssl-dev liblz4-tool u-boot-tools curl \
        expect g++ patchelf chrpath gawk texinfo diffstat binfmt-support \
        qemu-user-static live-build bison flex fakeroot cmake gcc-multilib \
        g++-multilib unzip device-tree-compiler python3-pip python2 libncurses5-dev \
        python3-pyelftools dpkg-dev pigz file \
        bc rsync build-essential \
        sudo \
        openssh-client ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 预装 repo 工具 (从清华镜像)
RUN curl -sSL https://mirrors.tuna.tsinghua.edu.cn/git/git-repo/repo \
        -o /usr/local/bin/repo && \
    chmod +x /usr/local/bin/repo

WORKDIR /workspace
