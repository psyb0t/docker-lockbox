FROM ubuntu:24.04

ARG LOCKBOX_UID=1000
ARG LOCKBOX_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV LOCKBOX_USER=lockbox

# Install SSH server and Python3
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        python3 \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create lockbox user
RUN if getent group ${LOCKBOX_GID} > /dev/null 2>&1; then \
        groupmod -n lockbox $(getent group ${LOCKBOX_GID} | cut -d: -f1); \
    else \
        groupadd -g ${LOCKBOX_GID} lockbox; \
    fi && \
    if getent passwd ${LOCKBOX_UID} > /dev/null 2>&1; then \
        usermod -l lockbox -g lockbox -d /home/lockbox -m $(getent passwd ${LOCKBOX_UID} | cut -d: -f1); \
    else \
        useradd -m -u ${LOCKBOX_UID} -g lockbox -s /bin/bash lockbox; \
    fi

# Setup directories
# authorized_keys lives under /etc/lockbox/ instead of /home/lockbox/ to avoid
# overlay2 bind mount issues with home dirs created via usermod -m
RUN mkdir -p /var/run/sshd /work /etc/lockbox/entrypoint.d && \
    chown lockbox:lockbox /work /home/lockbox && \
    chmod 755 /work && \
    touch /etc/lockbox/authorized_keys && \
    chmod 644 /etc/lockbox/authorized_keys

# Default empty allowed commands config
COPY allowed.json /etc/lockbox/allowed.json

# Copy configs
COPY sshd_config /etc/ssh/sshd_config
COPY --chmod=755 lockbox-wrapper /usr/local/bin/lockbox-wrapper
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Generate host keys
RUN ssh-keygen -A

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
