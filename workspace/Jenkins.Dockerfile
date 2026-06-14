FROM jenkins/jenkins:lts

USER root

RUN apt update && \
    apt install -y --no-install-recommends \
        gcc-aarch64-linux-gnu \
        libc6-dev-arm64-cross \
        make \
        file \
        qemu-user-static \
    && apt clean && \
    rm -rf /var/lib/apt/lists/*

USER jenkins
