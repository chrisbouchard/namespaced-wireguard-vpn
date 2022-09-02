# Namespaced WireGuard VPN

[![Copr build status][namespaced-wireguard-vpn-status-img]][namespaced-wireguard-vpn]

Systemd configuration for a network namespace containing a WireGuard VPN connection

## Overview

```
        I N T E R N E T
              Λ :
              | :
              | :
+------------ | : ------------+    +-----------------------------------------------+
| Init NS     | :             |    | VPN NS                                        |
|          -- V --            |    |      --------                                 |
|        / enp0s3  \ .................. / wg-vpn   \ .............                 |
|        \ 1.2.3.4 <--------------------> 10.0.0.1 /             :                 |
|          -------            |    |      --------       O------ : ------------O   |
|                             |    |                     | transmission-daemon |   |
|         ----------          |    |     ----------      O------------ : ------O   |
|       / veth─init  <-----------------> veth─vpn   \                  :           |
|       \ 10.127.0.1 / ............... \ 10.127.0.2 / .................:           |
|         ----------          |    |     ----------                                |
|              :              |    |                                               |
|   O--------- : ---------O   |    +-----------------------------------------------+
|   | transmission-remote |   |
|   O---------------------O   |
|                             |
+-----------------------------+
```

Rough illustration of the intended setup. See [Routing & Network Namespace
Integration][wireguard-namespace] for a more thorough explanation of how
WireGuard works across network namespaces.

If multiple layered VPN connections are used, a layout such as the one below 
will be created. This is useful for additional privacy, as multiple VPN providers
would need to be compromised for any information to be leaked. Assuming none of 
the VPN providers is a bottleneck, each additional layer only reduces the
performance achievable by about 10% due to protocol overheads.
```
        I N T E R N E T
              Λ :
              | :
              | :
+------------ | : ------------+    +-------------------+
| Init NS     | :             |    | VPN NS1           |
|          -- V --            |    |      --------     |
|        / enp0s3  \ .................. / wg-vpn1  \.....................
|        \ 1.2.3.4 <--------------------> 10.0.0.1 <-------------------+:
|          -------            |    |      --------     |               |:
|                             |    |                   |               |:
|   O---------------------O   |    +-------------------+               |:
|   | transmission-remote |   |                                        |:
|   O---------:-----------O   |    +-----------------------------------|:--------+
|             :               |    | VPN NS2                           |:        |
|         ----------          |    |      ----------               ----v---      |
|       / veth─init  <------------------> veth-vpn   \           / wg-vpn2  \    |
|       \ 10.127.0.1 / .................\ 10.127.0.2 /           \ 10.0.0.1 /    |
|         ----------          |    |      ----------               --------      |
|                             |    |             :                 :             |
+-----------------------------+    |           O : --------------- : O           |
                                   |           | transmission-daemon |           |
                                   |           O---------------------O           |
                                   |                                             |
                                   +---------------------------------------------+
```

## Installation

This package is available from the
[chrisbouchard/upliftinglemma][chrisbouchard/upliftinglemma] COPR. Assuming
you're using a recent version of Fedora or CentOS, you can install using `dnf`.

```console
$ dnf copr enable chrisbouchard/upliftinglemma
$ dnf install namespaced-wireguard-vpn
```

You may have to agree to some prompts if this is the first COPR you've enabled.

## Configuration

The systemd unit configuration file for this project is
`/etc/namespaced-wireguard-vpn/namespaced-wireguard-vpn.conf` which, by
default, is owned by root with 0600 permissions since it will contain your VPN
WireGuard private key. The file will be read as a systemd environment file (see
the [`EnvironmentFile=` directive in `systemd.exec(5)`][environmentfile=]). All
expected values are set by default, most with dummy default values.

#### Configuration Values

- `NETNS_NAME`:
  Name to assign to the created network namespace. Network namespace names are
  system global, so it's important that this name be unique.
  For using multiple layers, use multiple names separated by spaces.
- `WIREGUARD_NAME`:
  Name to assign to the created WireGuard network interface. The interface is
  created in the default (init) namespace then moved to the VPN namespace, so
  the interface name must be unique in both.
  For using multiple layers, use multiple names separated by spaces.
- `WIREGUARD_PRIVATE_KEY`:
  Private key assigned by the VPN provider for your WireGuard connection. _This
  is sensitive,_ so by default the configuration directory and file are only
  readable by root.
  For using multiple layers, set multiple private keys separated by spaces.
- `WIREGUARD_ENDPOINT`:
  The endpoint of the VPN provider's WireGuard server.
  For using multiple layers, set multiple endpoints separated by spaces.
- `WIREGUARD_VPN_PUBLIC_KEY`:
  The public key of the VPN provider's WireGuard peer.
  For using multiple layers, set multiple public keys separated by spaces.
- `WIREGUARD_ALLOWED_IPS`:
  Comma-separated list of IP addresses that may be contacted using the
  WireGuard interface. For a namespaced VPN, where the goal is to force all
  traffic through the VPN, the catch-all value `0.0.0.0/0,::0/0` is probably
  correct.
- `WIREGUARD_IP_ADDRESSES`:
  Comma-separated list of static IP addresses to assign to the WireGuard
  interface. As far as I know, WireGuard does not currently support DHCP or any
  other form of dynamic IP address assignment.
- `WIREGUARD_INITIAL_MTU`:
  MTU of the wireguard interface. Only applies to the initial layer if using
  multiple layers. Subsequent layers will have their MTUs reduced by 80 such
  as to avoid fragmentation or packet loss.
- `TUNNEL_ENABLE`:
  Whether to create the tunnel (veth) network interface between the default
  (init) and VPN network namespaces. Set to zero to disable or nonzero to
  enable.
- `TUNNEL_INIT_NAME`:
  Name to assign to the created tunnel (veth) network interface in the default
  (init) network namespace.
- `TUNNEL_INIT_IP_ADDRESSES`:
  Comma-separated list of static IP addresses to assign to the tunnel interface
  in the default (init) network namespace.
- `TUNNEL_VPN_NAME`:
  Name to assign to the created tunnel (veth) network interface in the VPN
  network namespace.
- `TUNNEL_VPN_IP_ADDRESSES`:
  Comma-separated list of static IP addresses to assign to the tunnel interface
  in the VPN network namespace.
  
#### Tunnel

This package provides a tunnel between the init namesapce and the created VPN
namespace so, e.g., you can control services inside the VPN namespace from
outside. If you don't need or want the tunnel, just set `TUNNEL_ENABLE=0`.

#### Namespace Overlay

Most likely, there will be some additional configuration that you will want to
make, particularly if your system uses `systemd-resolved` for domain name
resolution. Since `systemd-resolved` uses a UNIX socket, it won't be namespaced
and requests over the VPN will use the configured DNS name servers&nbsp;&mdash;
name resolution will either break (if configured to use local servers) or worse
leak information.

Linux network namespaces allow you to add configuration files in
`/etc/netns/$NETNS_NAME`, which will replace the existing configuration file
for processes running inside the namespace. I'd recommend overriding
`nsswitch.conf` and `resolv.conf` to use your VPN provider's name servers. 
If using multiple namespaces, this must be done for each seperately.
See [DNS Leaks with Network Namespaces][dns-leaks-with-netns] for more detail.

## Running

Once the configuration is done, you can start the VPN with

```console
$ systemctl start namespaced-wireguard-vpn.target
```

If you would like it to always start on boot, you can enable it with

```console
$ systemctl enable namespaced-wireguard-vpn.target
```

At this point, if there are no errors, you should have a new network namespace
(by default named `vpn`). You can test it out by running some commands in the
default (init) namespace and VPN namespace and comparing the output.

```console
$ curl ifconfig.me/ip
$ ip netns exec $NETNS_NAME curl ifconfig.me/ip
```

You may want to confirm that DNS requests are going to your VPN's name servers.

```console
$ nslookup example.com
$ ip netns exec $NETNS_NAME nslookup example.com
```

## Configuring Other Units to Run in the Namespace

While `ip netns exec` is handy for one-off commands, this project is most
useful to allow running other systemd units in a VPN-only namespace. This is accomplished by
adding a drop-in override file to the unit. In the following example, we'll configure
Transmission Daemon to run in our namespace.

#### `/etc/systemd/system/transmission-daemon.service.d/10-vpn-netns.conf`:

```systemd
[Unit]
BindsTo=namespaced-wireguard-vpn-netns.service
After=namespaced-wireguard-vpn-netns.service
JoinsNamespaceOf=namespaced-wireguard-vpn-netns.service

[Service]
PrivateNetwork=yes
```

## Future Work/TODO

- Consider using `sd_notify` for service scripts to provide a status.
- Once systemd 247 is widely available (probably when Fedora 34 is released),
  switch to using `LoadCredentials=` for the WireGuard private key.

## Contributing

The configuration is geared for a Mullvad configuration, since that's the VPN I
use, but I think it should be general enough to work with any simple WireGuard
VPN setup that `wg-quick` could handle. If you need something more complicated,
feel free to fork and open a merge request.

[chrisbouchard/upliftinglemma]: https://copr.fedorainfracloud.org/coprs/chrisbouchard/upliftinglemma
[dns-leaks-with-netns]: https://philipdeljanov.com/posts/2019/05/31/dns-leaks-with-network-namespaces/
[environmentfile=]: https://www.freedesktop.org/software/systemd/man/systemd.exec.html#EnvironmentFile=
[namespaced-wireguard-vpn-status-img]: https://copr.fedorainfracloud.org/coprs/chrisbouchard/upliftinglemma/package/namespaced-wireguard-vpn/status_image/last_build.png
[namespaced-wireguard-vpn]: https://copr.fedorainfracloud.org/coprs/chrisbouchard/upliftinglemma/package/namespaced-wireguard-vpn/
[wireguard-namespace]: https://www.wireguard.com/netns/
