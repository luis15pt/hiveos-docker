# HiveOS client as a self-contained GPU container (e.g. a RunPod pod).
# Needs only the GPUs passed in plus HIVE_ID/HIVE_PASS env vars; no mounts.
# Built on the unofficial hanaik/hiveos image, pinned to the digest we reviewed.
FROM hanaik/hiveos@sha256:db72f63ece8b73d3e1fe575bd98b8e1e83d7d32490d41734ad0c05fe67d72c94

# The base image ships its author's rig credentials as defaults. Blank them so
# a missing value can never connect our GPUs to their farm.
ENV HIVE_ID= HIVE_PASS= HIVE_WORKER= HIVE_TOKEN=

# Tools HiveOS scripts expect but the base image lacks:
#   ip (iproute2), lsusb (usbutils), dmidecode, crontab (cron), fgconsole (kbd)
RUN apt-get update \
 && apt-get install -y --no-install-recommends iproute2 usbutils dmidecode cron kbd \
 && rm -rf /var/lib/apt/lists/*

# /etc/start.sh downloads and installs an NVIDIA userspace driver on every
# start. The NVIDIA Container Toolkit already provides the host's driver
# libraries, so skip it.
RUN sed -i 's/install_nvidia_driver;//' /etc/start.sh \
 && ! grep -q '^[^#]*install_nvidia_driver;' /etc/start.sh

# HiveOS 0.6-225 drops GPU power readings above 500 W (reports 0). RTX 5090s
# draw up to 600 W. Backport the 1500 W cap from HiveOS 0.6-231.
RUN sed -i 's/^POWER_MAX=500$/POWER_MAX=1500/' /hive/bin/sanitize \
 && grep -q '^POWER_MAX=1500' /hive/bin/sanitize

# Our scripts (see README):
#   /hive/sbin/nvtool          nvidia-smi based replacement for HiveOS's nvtool,
#                              which refuses to run outside genuine HiveOS
#   /usr/local/sbin/lspci      shows HiveOS only the GPUs passed to the container
#   /usr/local/sbin/lsmod      reports the nvidia module on WSL2 (no kernel module)
#   /usr/local/sbin/quiet-wrapper  hides container-only errors (see below)
#   /usr/local/bin/miner-logs  streams the miner log to `docker logs`
COPY rootfs/ /

# Quieten tools HiveOS calls that can't work in a container (no systemd, D-Bus,
# /dev/mem, console or kernel modules): harmless failures that flood the logs.
RUN for c in systemctl timedatectl hostnamectl loginctl networkctl resolvectl \
             dmidecode fgconsole modprobe modinfo update-initramfs; do \
      ln -s quiet-wrapper /usr/local/sbin/$c; \
    done

# Don't print the rig password in the logs (startup rig.conf dump and the
# server's hello response, which is only parsed for display).
RUN sed -i 's|^cat /hive-config/rig.conf$|sed "s/^RIG_PASSWD=.*/RIG_PASSWD=********/" /hive-config/rig.conf|' /entrypoint.sh \
 && grep -q 'RIG_PASSWD=\*\*\*' /entrypoint.sh
RUN <<'EOF' python3
p = "/hive/bin/hello"
s = open(p).read()
old = """parsed=`echo "$response" | jq ${NOCOLOR:+-C} '.' 2>/dev/null`"""
new = """parsed=`echo "$response" | jq ${NOCOLOR:+-C} '(.result.config? // empty) |= gsub("RIG_PASSWD=[^\\n]*"; "RIG_PASSWD=********")' 2>/dev/null`"""
assert s.count(old) == 1, "hello: display line not found"
open(p, "w").write(s.replace(old, new))
EOF

# After startup, stream the miner log to stdout so `docker logs` shows mining
# output instead of going quiet (replaces start.sh's sleep-forever loop body).
RUN sed -i 's|^    sleep 86400  # Sleep for 24 hours$|    /usr/local/bin/miner-logs|' /etc/start.sh \
 && grep -q '^    /usr/local/bin/miner-logs$' /etc/start.sh

LABEL org.opencontainers.image.title="hiveos-docker" \
      org.opencontainers.image.description="HiveOS client as a self-contained GPU container" \
      org.opencontainers.image.source="https://github.com/luis15pt/hiveos-docker"
