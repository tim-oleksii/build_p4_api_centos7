FROM centos:7

# 0. The pre-requisites for this task are devtoolset and aria2c.
# C++17 is required to build P4 API, which is provided by devtoolset-11.
# Vim here is totally optional, as
RUN yum update -y \
 && yum install -y centos-release-scl epel-release \
 && yum-config-manager --enable rhel-server-rhscl-7-rpms \
 && yum install -y devtoolset-11 aria2 perl-IPC-Cmd vim \
 && yum clean all
SHELL [ "/usr/bin/scl", "enable", "devtoolset-11" ]

# 1. build OpenSSL as an additional dependency of P4 API C/C++.
# Perforce encourages to use the most recent version of OpenSSL.
# However, P4 API C/C++ compilation produces a lot of warnings.
# They are located in the code that uses OpenSSL.
RUN mkdir -p ~/openssl \
    && cd ~/openssl \
    && aria2c -x16 -j16 https://www.openssl.org/source/openssl-3.2.1.tar.gz \
    && tar -xf openssl-3.2.1.tar.gz --strip-component=1 \
    && rm -rf openssl-3.2.1.tar.gz \
    && ./Configure -fPIC --prefix=/usr/local/openssl --openssldir=/usr/local/openssl \
    && make -j`nproc` \
    && make -j`nproc` install \
    && make clean

# 2. Now let's install CMake via download script, as there is no CMake 3.19 required for P4 API .Net
RUN mkdir -p ~/cmake \
    && cd ~/cmake \
    && aria2c -x16 -j16 https://github.com/Kitware/CMake/releases/download/v3.28.3/cmake-3.28.3-linux-x86_64.sh \
    && chmod +x cmake-3.28.3-linux-x86_64.sh \
    && ./cmake-3.28.3-linux-x86_64.sh --skip-license --prefix=/usr/local \
    && rm -rf cmake-3.28.3-linux-x86_64.sh

# 3. step -- setup JAM to build P4 API C/C++.
# There is a deliberate need to optimize the output of compiler manually.
# Somehow perforce didnt think about any optimization parameters.
RUN mkdir -p ~/jam \
    && cd ~/jam \
    && aria2c https://swarm.workshop.perforce.com/downloads/guest/perforce_software/jam/jam-2.6.1.tar \
    && tar -xf jam-2.6.1.tar --strip-component=1 \
    && rm -rf jam-2.6.1.tar \
    && make -j`nproc` CFLAGS="-Os -flto=auto" \
    && cp ~/jam/bin.linuxx86_64/jam /usr/local/bin

# 4. Proceed with compilation of P4 API C/C++.
# It's critical to mention p4api.tgz as the build target.
# Without it errors of missing files pop up which cannot be solved.
# One more thing -- PIC is required for p4bridge to be built.
# Without it for sure no SO be linked.
# Optimisation is `O2` which is good but not the most aggressive one.
RUN mkdir -p ~/perforce_api \
    && cd ~/perforce_api \
    && aria2c -x16 -j16 https://ftp.perforce.com/perforce/r23.1/bin.tools/p4source.tgz \
    && tar -xf p4source.tgz --strip-component=1 \
    && rm -rf p4source.tgz \
    && jam -j`nproc` \
        -sOSVER=26 \
        -sMALLOC_OVERRIDE=no \
        -sSMARTHEAP=no \
        -sSSLINCDIR=/usr/local/openssl/include/ \
        -sSSLLIBDIR=/root/openssl/ \
        -sPRODUCTION=1 \
        -sTYPE=pic \
        p4api.tgz

# 5. The final part - build p4bridge C++ layer for .NET
# It mostly goes without tricks but following is not mentioned
# - you need to place libraries in exact places where cmake tries to find them. this is particularly difficult due to `devtoolset` environment being run.
# - it still requires OpenSSL. It makes sense, since SO is basically ELF.
RUN mkdir -p ~/p4_api_net \
    && cd ~/p4_api_net \
    && aria2c -x16 -j16 https://github.com/perforce/p4api.net/archive/refs/tags/2023.1.1.tar.gz \
    && tar -xf p4api.net-2023.1.1.tar.gz --strip-component=1 \
    && rm -rf p4api.net-2023.1.1.tar.gz \
    && mkdir -p p4api/include \
    && ln -s ~/p4-bin/bin.linux26x86_64/pic/p4api-2023.1.2534247/include/p4 p4api/include \
    && ln -s ~/p4-bin/bin.linux26x86_64/pic/p4api-2023.1.2534247/lib p4api \
    && cp /usr/local/openssl/lib64/libssl.a p4api/lib \
    && cp /usr/local/openssl/lib64/libcrypto.a p4api/lib \
    && cd /root/p4_api_net/p4bridge \
    && chmod +x buildrelease_linux.sh \
    && ./buildrelease_linux.sh

