## Prepare

Create a file named l2tp-ipsec.env
```
VPN_SERVER_IP='xxx.xxx.xxx.xxx'
VPN_IPSEC_PSK='my pre shared key'
VPN_USER='myuser@myhost.com'
VPN_PASSWORD='mypass'

PRIVATE_LAN_DNS=192.168.123.123
PRIVATE_LAN_HEALTH_CHECK=192.168.123.254
PRIVATE_LAN_IP_SUBNET=192.168.123.0/24
```

> **Note:** The default routing table settings are designed to exclusively route private LAN traffic ONLY.

Create a file named append-etc-hosts.sh
```
echo '# fixed dns' >> /etc/hosts
echo 192.168.123.123 host.domain >> /etc/hosts
```

## Run
```
docker run --privileged -d --name l2tp-ipsec \
    --restart unless-stopped \
    -v /lib/modules:/lib/modules:ro \
    -v ./l2tp-ipsec.env:/l2tp-ipsec.env \
    -v ./append-etc-hosts.sh:/append-etc-hosts.sh \
    -p 8118:8118 \
    --health-cmd='ping 192.168.123.123 -c 1 -W 1 || exit 1' \
    --health-timeout=1s \
    --health-retries=3 \
    --health-interval=10s \
    juouyang/l2tp-ipsec-http-proxy:1.0.3
docker logs -f l2tp-ipsec
```

## References

* [Configure Linux VPN clients using the command line](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/clients.md#configure-linux-vpn-clients-using-the-command-line)
* [IPsec IKEv1 weak legacy algorithms and backwards compatibility](https://github.com/nm-l2tp/NetworkManager-l2tp/blob/2926ea0239fe970ff08cb8a7863f8cb519ece032/README.md#ipsec-ikev1-weak-legacy-algorithms-and-backwards-compatibility)