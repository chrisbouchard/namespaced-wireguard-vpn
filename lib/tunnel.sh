#!/usr/bin/env bash

source base.sh

case "$1"
    up)
        ip link add "$TUNNEL_INIT_NAME" type veth \
            peer "$TUNNEL_VPN_NAME" netns "$NETNS_NAME" || die

        # Addresses are comma-separated, so to split them.
        xargs -d ',' -I '{}' \
            ip address add '{}' dev "$TUNNEL_INIT_NAME" \
            <<<"$TUNNEL_INIT_IP_ADDRESSES" || die
        xargs -d ',' -I '{}' \
            ip -n "$NETNS_NAME" address add '{}' dev "$TUNNEL_VPN_NAME" \
            <<<"$TUNNEL_VPN_IP_ADDRESSES" || die

        ip link set "$TUNNEL_INIT_NAME" up || die
        ip -n "$NETNS_NAME" link set "$TUNNEL_VPN_NAME" up || die
        ;;

    down)
        EXIT_CODE=0
        ip link delete "$TUNNEL_INIT_NAME" || EXIT_CODE=$?
        ip -n "$NETNS_NAME" link delete "$TUNNEL_VPN_NAME" || EXIT_CODE=$?
        [[ EXIT_CODE -eq 0 ]] || die
        ;;
esac

