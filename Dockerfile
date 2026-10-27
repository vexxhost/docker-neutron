# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

FROM rust@sha256:bf5a9aa29062a6cb03c49bd59a46eb55e3cc770caf598a221a7866e500be3082 AS ovsinit
WORKDIR /src
COPY --from=ovsinit-src / /src
RUN cargo install --path .

FROM ghcr.io/vexxhost/openstack-venv-builder:2025.1@sha256:8ab423cbd6a213eccba5e20bb69feae34ec71af5d748fa9759615f7c4a1a3f85 AS build
ARG NEUTRON_VERSION=26.0.5+a8e.14.6
RUN \
  --mount=type=bind,from=neutron-dynamic-routing,source=/,target=/src/neutron-dynamic-routing,readwrite \
  --mount=type=bind,from=neutron-vpnaas,source=/,target=/src/neutron-vpnaas,readwrite \
  --mount=type=bind,from=networking-baremetal,source=/,target=/src/networking-baremetal,readwrite \
  --mount=type=bind,from=networking-generic-switch,source=/,target=/src/networking-generic-switch,readwrite \
  --mount=type=bind,from=neutron-policy-checks,source=/,target=/src/neutron-policy-checks,readwrite \
  --mount=type=bind,from=neutron-ovn-network-logging-parser,source=/,target=/src/neutron-ovn-network-logging-parser,readwrite \
  --mount=type=bind,from=tap-as-a-service,source=/,target=/src/tap-as-a-service,readwrite <<EOF bash -xe
uv pip install \
    --constraint /upper-constraints.txt \
        "neutron==${NEUTRON_VERSION}" \
        /src/neutron-dynamic-routing \
        /src/neutron-vpnaas \
        /src/networking-baremetal \
        /src/networking-generic-switch \
        /src/neutron-policy-checks \
        /src/neutron-ovn-network-logging-parser \
        /src/tap-as-a-service \
        pymemcache
EOF

FROM ghcr.io/vexxhost/python-base:2025.1@sha256:608813acc8a21ca0d8dc94622ddf93a2c7319fa918be097357d2d61b70bae3c5
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
