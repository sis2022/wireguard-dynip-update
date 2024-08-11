#! /bin/bash
# Copyright 2023, 2024 N. Radtke
# License: GPLv2

declare -a DNS_SRV;
### Change or add you favourite DNS servers here
DNS_SRV=( "" "@8.8.8.8" "@8.8.8.8" );

get_ip() {
  local HOSTNAME="$1";
  local ADDRESS;

  for srv in "${DNS_SRV[@]}"; do
    if test -z "$ADDRESS"; then
      if ! ADDRESS="$(dig +noall +answer +timeout=3 +tries=3 +short -t A "${HOSTNAME}." "$srv" 2>/dev/null;)"; then
        ### dig error, reset error msg in ADDRESS
        ADDRESS="";
      fi;
    fi;
    if test -z "$ADDRESS"; then
      sleep 5;
    else
      break;
    fi;
  done;

  if test "$ADDRESS" = ""; then
    return;
  else
    echo "$ADDRESS";
  fi;
}

get_endpoint() {
  local IFACE="$1";
  local ENDPOINT;

  ### No need to refresh if non-existing endpoint.
  ENDPOINT=$(grep '^Endpoint' "/etc/wireguard/${IFACE}.conf" | sed 's/\s*//g' | cut -d '=' -f 2);
  [ -z "${ENDPOINT}" ] && return;
  echo "$ENDPOINT";
}

get_hostname() {
  local IFACE="$1";
  local ENDPOINT;
  local HOSTNAME;

  ENDPOINT=$(get_endpoint "$IFACE");
  [ -z "${ENDPOINT}" ] && return;
  HOSTNAME=$(echo "${ENDPOINT}" | cut -d : -f 1);
  [ -z "${HOSTNAME}" ] && return;
  echo "$HOSTNAME";
}

get_port() {
  local IFACE="$1";
  local ENDPOINT;
  local PORT;

  ENDPOINT=$(get_endpoint "$IFACE");
  [ -z "${ENDPOINT}" ] && return;
  PORT=$(echo "${ENDPOINT}" | cut -d : -f 2);
  [ -z "${PORT}" ] && return;
  echo "$PORT";
}

### inspired by: https://schinckel.net/2021/11/02/wireguard-and-dynamic-hostnames/
update_endpoint() {
  local IFACE="$1";
  local ENDPOINT;
  local HOSTNAME;
  local PORT;
  local PUBLIC_KEY;
  local ADDRESS;

  HOSTNAME=$(get_hostname "$IFACE");
  [ -z "${HOSTNAME}" ] && return 0;
  PORT=$(get_port "$IFACE");

  PUBLIC_KEY="$(wg show "${IFACE}" peers)";

  ### No need to refresh if no handshake
  [ -z "$(wg show "${IFACE}" latest-handshakes | grep "${PUBLIC_KEY}" | awk '{print $2}')" ] && return 0;

  ADDRESS=$(get_ip "$HOSTNAME");
  if test -z "$ADDRESS"; then
    return 0;
  fi;

  ### Return if we don't find any matching lines here - that means our IP address matches.
  ENDPOINT=$(wg show "${IFACE}" endpoints | grep "${PUBLIC_KEY}" 2>/dev/null);
  if echo "$ENDPOINT" | grep "${ADDRESS}" 1>/dev/null 2>&1; then
    return 0;
  fi;

  wg set "${IFACE}" peer "${PUBLIC_KEY}" endpoint "${ADDRESS}:${PORT}";
}

start_endpoint() {
  local IFACE="$1";
  local ADDRESS;
  local HOSTNAME;
  local TMP_DIR;
  local TMP_CFG;

  TMP_DIR=$(mktemp -p /tmp/ -d "${IFACE}_bootstrap_XXXXXXXXXX");
  TMP_CFG="${TMP_DIR}/${IFACE}.conf";

  HOSTNAME=$(get_hostname "$IFACE");
  [ -z "${HOSTNAME}" ] && return 0;

  ADDRESS=$(get_ip "$HOSTNAME");
  if test -z "$ADDRESS"; then
    return 0;
  fi;

  touch "$TMP_CFG";
  chmod 600 "$TMP_CFG";

  CFGADDRESS=$(grep -i "^Address" "/etc/wireguard/${IFACE}.conf");
  wg-quick strip "$IFACE" | grep -vE "^#|^$" | \
    sed "s/^Endpoint.*=.*:\([[:digit:]]\+\)$/Endpoint = ${ADDRESS}:\1/g; s/^\[Interface\]$/[Interface]\n${CFGADDRESS/\//\\/}/g" > "$TMP_CFG";
  wg-quick up "$TMP_CFG" 1>/dev/null 2>&1;
  rm "$TMP_CFG";
  rmdir "$TMP_DIR";
}

WG_IFS="";
WG_ACTIVE_IFS=$(wg show | grep "^interface: " | sed 's/^interface: //g');

for WG_CFG in /etc/wireguard/*.conf; do
  # shellcheck disable=SC2001
  CFG_IF=$(echo "$WG_CFG" | sed 's#.*/##g; s/.conf//g');
  # shellcheck disable=SC2143
  if [ "$(echo "$WG_ACTIVE_IFS" | grep "$CFG_IF")" ]; then
    WG_IFS="$WG_IFS $CFG_IF";
  else
    INACTIVE_IFS="$INACTIVE_IFS $CFG_IF";
  fi;
done;

for WG_IF in $WG_IFS ; do
  update_endpoint "$WG_IF";
done;

for INACTIVE_IF in $INACTIVE_IFS ; do
  start_endpoint "$INACTIVE_IF";
done;

### EOF
### vim:tw=80:et:sts=2:st=2:sw=2:com+=b\:###:fo+=cqtrw:tags=tags:
