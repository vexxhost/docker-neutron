# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: GPL-3.0-or-later

FROM rust@sha256:80302520b7199f0504975bca59a914015e9fee088f759875dbbc238ca9509ee1 AS ovsinit
WORKDIR /src
COPY --from=ovsinit-src / /src
RUN cargo install --path .

# TODO: move all this to the venv builder image
FROM ghcr.io/vexxhost/openstack-venv-builder:main@sha256:423e0a09ce69554f25fd508ceff39945fd16f01a5f2c7cfeeb9cf15a1c18ad33 AS builder
WORKDIR /src
ENV TOX_CONSTRAINTS_FILE=/upper-constraints.txt
ONBUILD RUN uvx tox -epy3
ONBUILD RUN uv build

FROM builder AS neutron-build
COPY --from=neutron / /src

FROM builder AS neutron-dynamic-routing-build
COPY --from=neutron-dynamic-routing / /src

FROM builder AS neutron-vpnaas-build
COPY --from=neutron-vpnaas / /src

FROM builder AS networking-baremetal-build
COPY --from=networking-baremetal / /src

FROM builder AS networking-generic-switch-build
COPY --from=networking-generic-switch / /src

FROM builder AS neutron-policy-server-build
COPY --from=neutron-policy-server / /src

FROM builder AS neutron-ovn-network-logging-parser-build
COPY --from=neutron-ovn-network-logging-parser / /src

FROM builder AS tap-as-a-service-build
COPY --from=tap-as-a-service / /src

FROM ghcr.io/vexxhost/openstack-venv-builder:main@sha256:423e0a09ce69554f25fd508ceff39945fd16f01a5f2c7cfeeb9cf15a1c18ad33 AS build
RUN \
  --mount=type=bind,from=neutron-build,source=/src/dist,target=/build/neutron \
  --mount=type=bind,from=neutron-dynamic-routing-build,source=/src/dist,target=/build/neutron-dynamic-routing \
  --mount=type=bind,from=neutron-vpnaas-build,source=/src/dist,target=/build/neutron-vpnaas \
  --mount=type=bind,from=networking-baremetal-build,source=/src/dist,target=/build/networking-baremetal \
  --mount=type=bind,from=networking-generic-switch-build,source=/src/dist,target=/build/networking-generic-switch \
  --mount=type=bind,from=neutron-policy-server-build,source=/src/dist,target=/build/neutron-policy-server \
  --mount=type=bind,from=neutron-ovn-network-logging-parser-build,source=/src/dist,target=/build/neutron-ovn-network-logging-parser \
  --mount=type=bind,from=tap-as-a-service-build,source=/src/dist,target=/build/tap-as-a-service <<EOF bash -xe
uv pip install \
  --constraint /upper-constraints.txt \
    /build/*/*.whl \
    pymemcache
EOF

FROM ghcr.io/vexxhost/python-base:main@sha256:df0f7c05b006fbfa355077571a42745b36e610e674c8ca77f5ac8de2e0fd0fba
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
