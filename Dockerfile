# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

FROM rust@sha256:1417b7faaabd8547ecd3c43f98fc5bd7f06295a40935bdbb81240210f7127f76 AS ovsinit
WORKDIR /src
COPY --from=ovsinit-src / /src
RUN cargo install --path .

FROM ghcr.io/vexxhost/openstack-venv-builder:2025.1@sha256:6036f39ccb28f3eac1a51d8519c919d2d5b0bf9198514c0f05d908e7a532d801 AS build
RUN \
  --mount=type=bind,from=neutron,source=/,target=/src/neutron,readwrite \
  --mount=type=bind,from=neutron-dynamic-routing,source=/,target=/src/neutron-dynamic-routing,readwrite \
  --mount=type=bind,from=neutron-vpnaas,source=/,target=/src/neutron-vpnaas,readwrite \
  --mount=type=bind,from=networking-baremetal,source=/,target=/src/networking-baremetal,readwrite \
  --mount=type=bind,from=networking-generic-switch,source=/,target=/src/networking-generic-switch,readwrite \
  --mount=type=bind,from=neutron-policy-server,source=/,target=/src/neutron-policy-server,readwrite \
  --mount=type=bind,from=neutron-ovn-network-logging-parser,source=/,target=/src/neutron-ovn-network-logging-parser,readwrite \
  --mount=type=bind,from=tap-as-a-service,source=/,target=/src/tap-as-a-service,readwrite <<EOF bash -xe
uv pip install \
    --constraint /upper-constraints.txt \
        /src/neutron \
        /src/neutron-dynamic-routing \
        /src/neutron-vpnaas \
        /src/networking-baremetal \
        /src/networking-generic-switch \
        /src/neutron-policy-server \
        /src/neutron-ovn-network-logging-parser \
        /src/tap-as-a-service \
        pymemcache
EOF

FROM ghcr.io/vexxhost/python-base:2025.1@sha256:d1078881aed91fe76f77d9a4320ba6df5a2bbc58bd84a8de4ff5be063a683046
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
