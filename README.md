# Namespaced WireGuard VPN

[![Copr build status][namespaced-wireguard-vpn-status-img]][namespaced-wireguard-vpn]

Systemd configuration for a network namespace containing a WireGuard VPN connection

## Installation

This package is available from the
[chrisbouchard/upliftinglemma][chrisbouchard/upliftinglemma] COPR. Assuming
you're using a recent version of Fedora or CentOS:

```console
$ dnf copr enable chrisbouchard/upliftinglemma
# Agree to any interactive prompts
$ dnf install namespaced-wireguard-vpn
```

## Configuration

The systemd unit configuration file for this project is
`/etc/namespaced-wireguard-vpn/namespaced-wireguard-vpn.conf` which, by
default, is owned by root with 0600 permissions since it will contain your VPN
WireGuard private key. The file will be read as a systemd environment file (see
the [`EnvironmentFile=` directive in `systemd.exec(5)`][environmentfile=]). All
expected values are set by default, most with dummy default values.

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
namespace:

```console
$ curl ifconfig.me/ip
$ ip netns exec $NETNS_NAME curl ifconfig.me/ip
```

## Configuring Other Units to Run in the Namespace

While `ip netns exec` is handy for one-off commands, this project is most
useful to allow running other systemd units in a VPN-only namespace. This is accomplished by
adding a drop-in override file to the unit. In the following example, we'll configure
Transmission Daemon to run in our namespace.

### `/etc/systemd/system/transmission-daemon.service.d/10-vpn-netns.conf`:

```systemd
[Unit]
BindsTo=namespaced-wireguard-vpn-netns.service
After=namespaced-wireguard-vpn-netns.service
JoinsNamespaceOf=namespaced-wireguard-vpn-netns.service

[Service]
PrivateNetwork=yes
```

## Contributing

The configuration is geared for a Mullvad configuration, since that's the VPN I
use, but I think it should be general enough to work with any simple WireGuard
VPN setup that `wg-quick` could handle. If you need something more complicated,
feel free to fork and open a merge request.

[chrisbouchard/upliftinglemma]: https://copr.fedorainfracloud.org/coprs/chrisbouchard/upliftinglemma
[namespaced-wireguard-vpn]: https://copr.fedorainfracloud.org/coprs/chrisbouchard/upliftinglemma/package/namespaced-wireguard-vpn/
[namespaced-wireguard-vpn-status-img]: https://copr.fedorainfracloud.org/coprs/chrisbouchard/upliftinglemma/package/namespaced-wireguard-vpn/status_image/last_build.png
[environmentfile=]: https://www.freedesktop.org/software/systemd/man/systemd.exec.html#EnvironmentFile=
[dns-leaks-with-netns]: https://philipdeljanov.com/posts/2019/05/31/dns-leaks-with-network-namespaces/
