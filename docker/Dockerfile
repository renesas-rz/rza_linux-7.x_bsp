FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential gcc g++ make file wget curl cpio unzip rsync bc \
    python3 python3-setuptools git patch perl libncurses-dev \
    bison flex libssl-dev libelf-dev device-tree-compiler kmod \
    locales sudo vim less srecord && \
    locale-gen en_US.UTF-8 && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID builder && useradd -m -u $UID -g $GID -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builder
USER builder
WORKDIR /work/rza_linux-7.x_bsp
