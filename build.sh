#!/bin/sh

# test environment: ubuntu 18.04+

UDP2RAW_PACKAGE_URL="https://github.com/wangyu-/udp2raw-tunnel/releases/download/20181113.0/udp2raw_binaries.tar.gz"
SPEEDER_PACKAGE_URL="https://github.com/wangyu-/UDPspeeder/releases/download/20190121.0/speederv2_binaries.tar.gz"
VPS_IPv4=$(curl ifconfig.co -4)
VPS_IPv6=$(curl ifconfig.co -6)

apt-get update
export DEBIAN_FRONTEND=noninteractive
apt-get upgrade -y
apt -y install libsodium-dev ufw moreutils jq curl wget tar util-linux gawk openssl resolvconf

random_number() {
    echo $(awk -v min=$1 -v max=$2 -v seed=$RANDOM 'BEGIN{srand(seed); print int(min+rand()*(max-min+1))}')
}

assign_parameters() {
    local ret=false
    local i=0
    until [ $ret = true ]; do
        local p=$(random_number 1100 65000)
        if ! [[ ${port_list[*]} =~ $p ]]; then
            port_list[$i]=$p
            if [ $i == 3 ]; then
                ret=true
            fi
            ((i++))
        fi
    done
    USER_ID=$(uuidgen -t)
    UDP_PASS=$(openssl rand -base64 15)
    SPEEDER_PASS=$(openssl rand -base64 15)
    V2RAY_PORT=${port_list[0]}
    SPEEDER_PORT=${port_list[1]}
    UDP2RAW_PORT=${port_list[2]}
    WIREGUARD_PORT=${port_list[3]}
}

install_udp2raw() {
    mkdir /root/udp2raw
    wget $UDP2RAW_PACKAGE_URL -O /root/udp2raw/udp2raw.tar.gz
    tar xf /root/udp2raw/udp2raw.tar.gz -C /root/udp2raw
    chmod +x /root/udp2raw/udp2raw_amd64

    cat <<EOF >/root/udp2raw/run.sh
#!/bin/sh
if [ "\$CHAIN_BREAKER_SPEEDER_ENABLE" == "true" ]; then
    REDIRECT_PORT=$SPEEDER_PORT
else
    if [ "\$CHAIN_BREAKER_PROXY_METHOD" == "wireguard" ]; then
        REDIRECT_PORT=$WIREGUARD_PORT
    else
        REDIRECT_PORT=$V2RAY_PORT
    fi
fi
if [ "\$CHAIN_BREAKER_IP_VERSION" == "ipv4" ]; then
    LOCAL_IP="127.0.0.1"
    ALL_IP="0.0.0.0"
else
    LOCAL_IP="[::1]"
    ALL_IP="[::]"
fi
/root/udp2raw/udp2raw_amd64 -s -l\$ALL_IP:$UDP2RAW_PORT -r\$LOCAL_IP:\$REDIRECT_PORT -k "$UDP_PASS" --raw-mode faketcp -a --disable-color --cipher-mode xor --auth-mode simple --sock-buf 10240 --force-sock-buf
EOF
    systemctl enable udp2raw.service
}

install_speeder() {
    mkdir /root/speeder
    wget $SPEEDER_PACKAGE_URL -O /root/speeder/speeder.tar.gz
    tar xf /root/speeder/speeder.tar.gz -C /root/speeder
    chmod +x /root/speeder/speederv2_amd64

    cat <<EOF >/root/speeder/run.sh
#!/bin/sh
if [ "\$CHAIN_BREAKER_PROXY_METHOD" == "wireguard" ]; then
    DESTINATION_PORT=$WIREGUARD_PORT
else
    DESTINATION_PORT=$V2RAY_PORT
fi
if [ "\$CHAIN_BREAKER_IP_VERSION" == "ipv4" ]; then
    LOCAL_IP="127.0.0.1"
else
    LOCAL_IP="[::1]"
fi
if [ "\$CHAIN_BREAKER_SPEEDER_MODE" == "web" ]; then
    /root/speeder/speederv2_amd64 -s -l"\$LOCAL_IP:$SPEEDER_PORT" -r"127.0.0.1:\$DESTINATION_PORT" --disable-color -k "$SPEEDER_PASS" --mode 0 -f20:10
else
    /root/speeder/speederv2_amd64 -s -l"\$LOCAL_IP:$SPEEDER_PORT" -r"127.0.0.1:\$DESTINATION_PORT" --disable-color -k "$SPEEDER_PASS" --mode 0 -f2:4 -q1
fi
EOF
}

configure_services() {
    cat <<EOF >/etc/systemd/system/udp2raw.service
[Unit]
Description=udp2raw service
After=network.target
Wants=network.target

[Service]
EnvironmentFile=/root/chain_breaker.conf
ExecStart=/bin/bash /root/udp2raw/run.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    cat <<EOF >/etc/systemd/system/speeder.service
[Unit]
Description=speeder service
Requires=udp2raw.service

[Service]
EnvironmentFile=/root/chain_breaker.conf
ExecStart=/bin/bash /root/speeder/run.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
}

install_v2ray() {
    bash <(curl -L -s https://install.direct/go.sh)
    wget https://raw.githubusercontent.com/chaos-sudo/Cross-The-Wall/master/v2ray_default.json -O /tmp/tmp1.json
    jq .inbound.port=$V2RAY_PORT /tmp/tmp1.json >/tmp/tmp2.json
    jq .inbound.settings.clients[].id=\"$USER_ID\" /tmp/tmp2.json >/etc/v2ray/config.json
}

wireguard_client_config() {
    cat <<EOF >/tmp/client.config
[Interface]
PrivateKey = $2
Address = 10.0.0.$1/24
DNS = 8.8.8.8, 1.1.1.1
MTU = 1200

[Peer]
PublicKey = $3
AllowedIPs = ::/0, 0.0.0.0/0
Endpoint = 192.168.0.105:2111
PersistentKeepalive = 25
EOF
}

install_wireguard() {
    add-apt-repository ppa:wireguard/wireguard -y
    apt-get update
    apt-get install wireguard qrencode -y

    for i in {1..4}; do
        WG_KEY[$i]=$(wg genkey)
        WG_KEY_PUB[$i]=$(echo ${WG_KEY[$i]} | wg pubkey)
        if [ $i != 1 ]; then
            wireguard_client_config $i ${WG_KEY[1]} ${WG_KEY_PUB[$i]}
            qrencode -t ansiutf8 < /tmp/client.config > /root/client$i.qrcode
        fi
    done

    NET_INTERFACE=$(ls /sys/class/net | awk '/^e/{print}')
    cat <<EOF >/etc/wireguard/wg0.conf
[Interface]
  PrivateKey = ${WG_KEY[1]}
  Address = 10.0.0.1/24
  PostUp   = echo 1 > /proc/sys/net/ipv4/ip_forward; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $NET_INTERFACE -j MASQUERADE
  PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $NET_INTERFACE -j MASQUERADE
  ListenPort = $WIREGUARD_PORT
  DNS = 8.8.8.8, 1.1.1.1
  MTU = 1200

[Peer]
  PublicKey = ${WG_KEY_PUB[2]}
  AllowedIPs = 10.0.0.2/32
[Peer]
  PublicKey = ${WG_KEY_PUB[3]}
  AllowedIPs = 10.0.0.3/32
[Peer]
  PublicKey = ${WG_KEY_PUB[4]}
  AllowedIPs = 10.0.0.4/32
EOF
}

optimize_system() {
    echo "ulimit -n 65535" >>/etc/profile
    echo "net.core.default_qdisc=fq" >>/etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.conf
    echo "net.core.rmem_max=26214400" >>/etc/sysctl.conf
    echo "net.core.rmem_default=26214400" >>/etc/sysctl.conf
    echo "net.core.wmem_max=26214400" >>/etc/sysctl.conf
    echo "net.core.wmem_default=26214400" >>/etc/sysctl.conf
    echo "net.core.netdev_max_backlog=2048" >>/etc/sysctl.conf
    echo "net.core.default_qdisc=fq" >>/etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.conf
    sysctl -p
    sysctl --system
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow http
    ufw allow https
    ufw allow ssh
    ufw allow $V2RAY_PORT
    ufw allow $SPEEDER_PORT
    ufw allow $UDP2RAW_PORT
    ufw allow $WIREGUARD_PORT
    echo "y" | ufw enable
}

main() {
    assign_parameters
    install_wireguard
    install_v2ray
    install_udp2raw
    install_speeder
    configure_services
    optimize_system

    echo "v2ray uuid: $USER_ID" >/root/result.txt
    echo "IPv4: $VPS_IPv4" >>/root/result.txt
    echo "IPv6: $VPS_IPv6" >>/root/result.txt
    echo "v2ray port: $V2RAY_PORT" >>/root/result.txt
    echo "wireguard port: $WIREGUARD_PORT" >>/root/result.txt
    echo "udp2raw port: $UDP2RAW_PORT" >>/root/result.txt
    echo "udp2raw password: $UDP_PASS" >>/root/result.txt
    echo "speeder password: $SPEEDER_PASS" >>/root/result.txt
    echo "wireguard server key: ${WG_KEY_PUB[1]}" >>/root/result.txt
    echo "wireguard client2 key: ${WG_KEY[2]}" >>/root/result.txt
    echo "wireguard client3 key: ${WG_KEY[3]}" >>/root/result.txt
    echo "wireguard client4 key: ${WG_KEY[4]}" >>/root/result.txt

    wget https://raw.githubusercontent.com/chaos-sudo/Cross-The-Wall/master/ipv6_change.sh -O /root/ipv6_change.sh
    wget https://raw.githubusercontent.com/chaos-sudo/Cross-The-Wall/master/chain_breaker.sh -O /root/chain_breaker.sh
    bash ipv6_change.sh
    tar -C /root -cf config.tar.gz *.qrcode result.txt

    bash /root/chain_breaker.sh -i ipv6 -m wireguard -s game

    sleep 10
    reboot
}

main
