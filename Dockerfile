# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

FROM rust@sha256:eba5c67cda4029029754bab0fcd438aaa783f9c8612bda10a8b8f890e40b5a64 AS ovsinit
WORKDIR /src
COPY --from=ovsinit-src / /src
RUN cargo install --path .

FROM ghcr.io/vexxhost/openstack-venv-builder:zed@sha256:2d0e23a84be9865b146a583e54e9c70ec417d9f7eee45f7f286dec312282758f AS build
RUN \
  --mount=type=bind,from=neutron,source=/,target=/src/neutron,readwrite \
  --mount=type=bind,from=neutron-vpnaas,source=/,target=/src/neutron-vpnaas,readwrite \
  --mount=type=bind,from=networking-baremetal,source=/,target=/src/networking-baremetal,readwrite \
  --mount=type=bind,from=neutron-policy-server,source=/,target=/src/neutron-policy-server,readwrite \
  --mount=type=bind,from=neutron-ovn-network-logging-parser,source=/,target=/src/neutron-ovn-network-logging-parser,readwrite <<EOF bash -xe
uv pip install \
    --constraint /upper-constraints.txt \
        /src/neutron \
        /src/neutron-vpnaas \
        /src/networking-baremetal \
        /src/neutron-policy-server \
        /src/neutron-ovn-network-logging-parser
EOF

FROM ghcr.io/vexxhost/python-base:zed@sha256:aaebc3192ae08a1707356c70fa90e5d6127ada404318f7e85234a4b9e8084065
RUN \
    groupadd -g 42424 neutron && \
    useradd -u 42424 -g 42424 -M -d /var/lib/neutron -s /usr/sbin/nologin -c "Neutron User" neutron && \
    mkdir -p /etc/neutron /var/log/neutron /var/lib/neutron /var/cache/neutron && \
    chown -Rv neutron:neutron /etc/neutron /var/log/neutron /var/lib/neutron /var/cache/neutron
RUN <<EOF bash -xe
apt-get update -qq
apt-get install -qq -y --no-install-recommends \
    conntrack dnsmasq dnsmasq-utils ebtables ethtool haproxy iproute2 ipset iptables iputils-arping jq keepalived lshw openvswitch-switch strongswan uuid-runtime
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF
COPY --from=ovsinit /usr/local/cargo/bin/ovsinit /usr/local/bin/ovsinit
COPY --from=build --link /var/lib/openstack /var/lib/openstack
