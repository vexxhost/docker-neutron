# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

FROM rust@sha256:652612f07bfbbdfa3af34761c1e435094c00dde4a98036132fca28c7bb2b165c AS ovsinit
WORKDIR /src
COPY --from=ovsinit-src / /src
RUN cargo install --path .

FROM ghcr.io/vexxhost/openstack-venv-builder:2023.1@sha256:a991466691718ef3d9557da23c2e0f6a14e956fa21e5e99fbc6fb011872853d5 AS build
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

FROM ghcr.io/vexxhost/python-base:2023.1@sha256:d2702936a9577055998a971b9e2ee46170e0c39bc0713f89b0c589187802c4d5
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
