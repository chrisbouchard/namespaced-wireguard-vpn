#!/usr/bin/env bash

source base.sh

case "$1"
    up)
        ip netns add "$NETNS_NAME" || die

        if [[ -n "$PRIVATE_NETNS_BIND_MOUNT" ]]
        then
            umount "/var/run/netns/$NETNS_NAME" || die
            mount --bind "$PRIVATE_NETNS_BIND_MOUNT" "/var/run/netns/$NETNS_NAME" || die
        fi

        ip -n "$NETNS_NAME" link set lo up || die
        ;;

    down)
        ip netns delete "$NETNS_NAME" || die
        ;;
esac

