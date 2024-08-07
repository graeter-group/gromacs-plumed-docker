FROM nvidia/cuda:11.0.3-devel-ubuntu20.04 as builder

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Berlin

ARG JOBS=6

RUN cat /etc/apt/sources.list
#install dependencies
RUN apt-get update 
RUN apt-get install -y cmake g++ gcc 
RUN apt-get install -y libblas-dev xxd 
RUN apt-get install -y mpich libmpich-dev 
RUN apt-get install -y curl
RUN apt-get install -y unzip

RUN mkdir /build
WORKDIR /build


ARG PLUMED_VERSION=master

RUN apt-get update
RUN apt-get install -y git

ENV GIT_SSL_NO_VERIFY=true
RUN git clone https://github.com/plumed/plumed2.git plumed2 --branch ${PLUMED_VERSION} --single-branch

# RUN cd /build && \
#     curl https://download.pytorch.org/libtorch/cpu/libtorch-cxx11-abi-shared-with-deps-1.12.1%2Bcpu.zip --output torch.zip && \
#     unzip torch.zip && \
#     rm torch.zip

# ENV LIBTORCH=/build/libtorch
# ENV CPATH=${LIBTORCH}/include/torch/csrc/api/include/:${LIBTORCH}/include/:${LIBTORCH}/include/torch:$CPATH
# ENV INCLUDE=${LIBTORCH}/include/torch/csrc/api/include/:${LIBTORCH}/include/:${LIBTORCH}/include/torch:$INCLUDE
# ENV LIBRARY_PATH=${LIBTORCH}/lib:$LIBRARY_PATH
# ENV LD_LIBRARY_PATH=${LIBTORCH}/lib:$LD_LIBRARY_PATH
# RUN cd plumed2 && ./configure --enable-libtorch --enable-modules=all && make -j ${JOBS} && make install 

RUN cd plumed2 && ./configure --enable-modules=reset && make -j ${JOBS} && make install 
RUN ldconfig

RUN apt update
RUN apt install -y python3

ARG GROMACS_VERSION=2021
ARG GROMACS_MD5=176f7decc09b23d79a495107aaedb426
ARG GROMACS_PATCH_VERSION=${GROMACS_VERSION}

RUN curl -o gromacs.tar.gz https://ftp.gromacs.org/gromacs/gromacs-${GROMACS_VERSION}.tar.gz
RUN echo ${GROMACS_MD5} gromacs.tar.gz > gromacs.tar.gz.md5 && md5sum -c gromacs.tar.gz.md5

RUN tar -xzvf gromacs.tar.gz
RUN cd gromacs-${GROMACS_VERSION} && plumed patch -e gromacs-${GROMACS_PATCH_VERSION} -p

COPY build-gmx.sh /build
RUN ./build-gmx.sh -s gromacs-${GROMACS_VERSION} -j ${JOBS} -a SSE2
RUN ./build-gmx.sh -s gromacs-${GROMACS_VERSION} -j ${JOBS} -a SSE2 -d

RUN ./build-gmx.sh -s gromacs-${GROMACS_VERSION} -j ${JOBS} -a AVX2_256 -r
RUN ./build-gmx.sh -s gromacs-${GROMACS_VERSION} -j ${JOBS} -a AVX2_256 -r -d

RUN ./build-gmx.sh -s gromacs-${GROMACS_VERSION} -j ${JOBS} -a AVX_512 -r
RUN ./build-gmx.sh -s gromacs-${GROMACS_VERSION} -j ${JOBS} -a AVX_512 -r -d


# RUN apt-get install -y python3 python3-pip
# RUN pip3 install torch --extra-index-url https://download.pytorch.org/whl/cpu

FROM nvidia/cuda:11.0.3-runtime-ubuntu20.04

RUN apt update
RUN apt upgrade -y
RUN apt install -y mpich
RUN apt install -y libcufft10 libmpich12 libblas3 libgomp1 
RUN apt install -y rsync

# COPY --from=builder /build/libtorch /build/libtorch
# ENV LD_LIBRARY_PATH=/build/libtorch/lib:$LD_LIBRARY_PATH
# ENV CPLUS_INCLUDE_PATH=/build/libtorch/include:$CPLUS_INCLUDE_PATH

# COPY --from=builder /build/libtorch/lib/* /usr/local/lib/
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /usr/local/lib/libplumed* /usr/local/lib/
COPY --from=builder /usr/local/lib/plumed/ /usr/local/lib/plumed/

COPY --from=builder /gromacs /gromacs

COPY gmx-chooser.sh /gromacs
COPY gmx /usr/local/bin
RUN ln -s gmx /usr/local/bin/gmx_d
RUN ln -s gmx /usr/local/bin/mdrun
RUN ln -s gmx /usr/local/bin/mdrun_d

RUN apt-get install -y wget build-essential checkinstall  libreadline-gplv2-dev  libncursesw5-dev  libssl-dev  libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev libffi-dev zlib1g-dev

RUN cd /usr/src && \
    wget https://www.python.org/ftp/python/3.10.12/Python-3.10.12.tgz && \
    tar xzf Python-3.10.12.tgz && \
    cd Python-3.10.12 && \
    ./configure --enable-optimizations && \
    make install
RUN rm -r /usr/src/Python-3.10.12.tgz

RUN cd /usr/src && \
    wget https://www.python.org/ftp/python/3.11.4/Python-3.11.4.tgz && \
    tar xzf Python-3.11.4.tgz && \
    cd Python-3.11.4 && \
    ./configure --enable-optimizations && \
    make install
RUN rm -r /usr/src/Python-3.11.4.tgz

RUN cd /usr/src && \
    wget https://www.python.org/ftp/python/3.9.17/Python-3.9.17.tgz && \
    tar xzf Python-3.9.17.tgz && \
    cd Python-3.9.17 && \
    ./configure --enable-optimizations && \
    make install
RUN rm -r /usr/src/Python-3.9.17.tgz

RUN mkdir /venv
RUN cd /venv
RUN python3.9 -m pip install -U tox pip
RUN python3.10 -m pip install -U tox pip
RUN python3.11 -m pip install -U tox pip

RUN apt install -y nodejs
RUN apt install -y zip

RUN apt clean
RUN ldconfig
