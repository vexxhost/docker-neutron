# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

FROM rust@sha256:4a7e3a0c309c9bab658e469f842711bd595fae484936bc5d605e08ca0c631bf4 AS ovsinit
WORKDIR /src
COPY --from=ovsinit-src / /src
RUN cargo install --path .

FROM ghcr.io/vexxhost/openstack-venv-builder:2023.1@sha256:67080a680131cab8b6a881218f9a69fc511bdc2a7c8823f40bc617d10e6090a3 AS build
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

FROM ghcr.io/vexxhost/python-base:2023.1@sha256:16f0ef9748b7d689e54f45450370a8ec1bf1ed993e7e7b0ad5c9781d60c7dc75
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
