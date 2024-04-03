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
- `WIREGUARD_NAME`:
  Name to assign to the created WireGuard network interface. The interface is
  created in the default (init) namespace then moved to the VPN namespace, so
  the interface name must be unique in both.
- `WIREGUARD_PRIVATE_KEY`:
  Private key assigned by the VPN provider for your WireGuard connection. _This
  is sensitive,_ so by default the configuration directory and file are only
  readable by root.
- `WIREGUARD_ENDPOINT`:
  The endpoint of the VPN provider's WireGuard server.
- `WIREGUARD_VPN_PUBLIC_KEY`:
  The public key of the VPN provider's WireGuard peer.
- `WIREGUARD_VPN_PPRESHARED_KEY`:
  The preshared key of the VPN provider's WireGuard peer. Set to - to disable.
- `WIREGUARD_ALLOWED_IPS`:
  Comma-separated list of IP addresses that may be contacted using the
  WireGuard interface. For a namespaced VPN, where the goal is to force all
  traffic through the VPN, the catch-all value `0.0.0.0/0,::0/0` is probably
  correct.
- `WIREGUARD_INITIAL_MTU`:
  MTU of the wireguard interface. Choosing too large a value risks packet loss.
- `WIREGUARD_IP_ADDRESSES`:
  Comma-separated list of static IP addresses to assign to the WireGuard
  interface. As far as I know, WireGuard does not currently support DHCP or any
  other form of dynamic IP address assignment.
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

##### iptables rules

To control the services from outside the VPN as though they were running in the
physical namespace, rather than only having the accessible from this host, a 
few iptables rules are required. Here I'm assuming that `net.ipv4.ip_forward=1`
and that the `FORWARD` table is allowing forwarding between interfaces. 
```
iptables -t nat -A PREROUTING -i [PHYSICAL] -p tcp -m tcp --dport [PORT] -j DNAT --to-destination [TUNNEL_VPN_IP_ADDRESSES]:[PORT]
iptables -t nat -A POSTROUTING -d [TUNNEL_VPN_IP_ADDRESSES] -o [TUNNEL_VPN_NAME] -p tcp -m tcp --dport [PORT] -j MASQUERADE
```
For example with the standard settings to forward port 8000 from `eth0` you may use
```
iptables -t nat -A PREROUTING -i eth0 -p tcp -m tcp --dport 8000 -j DNAT --to-destination 10.127.0.2:8000
iptables -t nat -A POSTROUTING -d 10.127.0.2/32 -o veth-vpn0 -p tcp -m tcp --dport 8000 -j MASQUERADE
```

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
`nsswitch.conf` and `resolv.conf` to use your VPN provider's name servers. See
[DNS Leaks with Network Namespaces][dns-leaks-with-netns] for more detail.

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
Transmission Daemon to run in our namespace. Beware that is used in conjunction with the 
`nsswitch.conf` and `resolv.conf` tweaks above this will not work correctly, as systemd
does not mount them into the right locations. There using `ip netns exec` may be more
appropriate.

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
