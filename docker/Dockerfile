FROM ubuntu:latest

# set a directory for the app
WORKDIR /usr/src/

############### Only docker specific setup goes here ###############

# setup script
COPY setup_top_level_repo.sh setup_top_level_repo.sh
# ssh key for access to repos
COPY id_rsa.pub /root/.ssh/id_rsa.pub
COPY id_rsa /root/.ssh/id_rsa
COPY known_hosts /root/.ssh/known_hosts
# set proxies
COPY apt.conf /etc/apt/apt.conf
COPY proxy.sh /etc/profile.d/proxy.sh
COPY .wgetrc /root/.wgetrc
RUN cat /etc/profile.d/proxy.sh >> /etc/environment
RUN cat /etc/profile.d/proxy.sh >> /root/.profile
RUN cat /etc/profile.d/proxy.sh >> /root/.bashrc

RUN apt update

# Setup timezone
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Los_Angeles
RUN apt install -y tzdata

# Setup sudo
RUN apt -y install sudo
# Disable annoying warning when using sudo
COPY sudo.conf /etc/sudo.conf
# Set private key permissions
RUN chmod 400 /root/.ssh/id_rsa

# install editor for convenience
RUN apt install -y nano

# Setup shell env
ENV SHELL=/bin/bash

############### Get the top level repo and run setup ###############
RUN ./setup_top_level_repo.sh

# Run the test automatically on startup
CMD ["bash", "-c", "source /etc/profile.d/proxy.sh && cd /usr/src/lim_rlbox_firefox_root; make pull && make build_guest_debug && make build_guest_release; bash"]
