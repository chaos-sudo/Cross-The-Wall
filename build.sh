#!/bin/sh

# test environment: ubuntu 18.04+

UDP2RAW_PACKAGE_URL="https://github.com/wangyu-/udp2raw-tunnel/releases/download/20181113.0/udp2raw_binaries.tar.gz"
VPS_IPv4=$(curl ifconfig.co -4)
VPS_IPv6=$(curl ifconfig.co -6)

apt-get update
export DEBIAN_FRONTEND=noninteractive
apt-get upgrade -y
apt -y install libsodium-dev ufw moreutils jq curl wget tar util-linux gawk openssl

function random_number() {
    echo $(awk -v min=$1 -v max=$2 -v seed=$RANDOM 'BEGIN{srand(seed); print int(min+rand()*(max-min+1))}')
}

function specifying_parameters() {
    local ret=false
    local i=0
    until [ $ret = true ]; do
        local p=$(random_number 1100 65000)
        if ! [[ ${port_list[*]} =~ $p ]]; then
            port_list[$i]=$p
            if [ $i == 4 ]; then
                ret=true
            fi
            ((i++))
        fi
    done
    USER_ID=$(uuidgen -t)
    UDP_PASS=$(openssl rand -base64 15)
    V2RAY_PORT=${port_list[0]}
    KCPTUN_IPV4_PORT=${port_list[1]}
    KCPTUN_IPV6_PORT=${port_list[2]}
    UDP2RAW_IPV4_PORT=${port_list[3]}
    UDP2RAW_IPV6_PORT=${port_list[4]}
}

function configuring_kcptun() {
    mkdir /root/kcptun
    wget $(curl -s https://api.github.com/repos/xtaci/kcptun/releases/latest 2>/dev/null | jq -r '.assets[] | select(.browser_download_url | contains("linux-amd64")) | .browser_download_url') -O /root/kcptun/kcptun.tar.gz
    tar xf /root/kcptun/kcptun.tar.gz -C /root/kcptun
    chmod +x /root/kcptun/server_linux_amd64
    cat <<EOF >/root/kcptun/run.sh
if [ "\$1" == "ipv4" ]; then
    LOCAL_IP="127.0.0.1"
    PORT_LISTEN=$KCPTUN_IPV4_PORT
else
    LOCAL_IP="[::1]"
    PORT_LISTEN=$KCPTUN_IPV6_PORT
fi
/root/kcptun/server_linux_amd64 -t "\$LOCAL_IP:$V2RAY_PORT" -l "\$LOCAL_IP:\$PORT_LISTEN" -mode fast3 -mtu 1250 --crypt none -sockbuf 16777217
EOF
}

function configuring_udp2raw() {
    mkdir /root/udp2raw
    wget $UDP2RAW_PACKAGE_URL -O /root/udp2raw/udp2raw.tar.gz
    tar xf /root/udp2raw/udp2raw.tar.gz -C /root/udp2raw
    chmod +x /root/udp2raw/udp2raw_amd64
    cat <<EOF >/root/udp2raw/run.sh
if [ "\$1" == "ipv4" ]; then
    LOCAL_IP="127.0.0.1"
    ALL_IP="0.0.0.0"
    KCPTUN_PORT=$KCPTUN_IPV4_PORT
    UDP2RAW_PORT=$UDP2RAW_IPV4_PORT
else
    LOCAL_IP="[::1]"
    ALL_IP="[::]"
    KCPTUN_PORT=$KCPTUN_IPV6_PORT
    UDP2RAW_PORT=$UDP2RAW_IPV6_PORT
fi
/root/udp2raw/udp2raw_amd64 -s -l\$ALL_IP:\$UDP2RAW_PORT -r\$LOCAL_IP:\$KCPTUN_PORT -k "$UDP_PASS" --raw-mode faketcp -a --disable-color  --cipher-mode xor --auth-mode simple
EOF
}

function configuring_services() {
    wget https://raw.githubusercontent.com/chaos-sudo/Cross-The-Wall/master/chain_breaker.service -O /etc/systemd/system/chain_breaker.service
    wget https://raw.githubusercontent.com/chaos-sudo/Cross-The-Wall/master/chain_breaker-udp2raw%40.service -O /etc/systemd/system/chain_breaker-udp2raw@.service
    wget https://raw.githubusercontent.com/chaos-sudo/Cross-The-Wall/master/chain_breaker-kcptun%40.service -O /etc/systemd/system/chain_breaker-kcptun@.service
    systemctl enable chain_breaker chain_breaker-udp2raw@ipv4 chain_breaker-kcptun@ipv4 chain_breaker-udp2raw@ipv6 chain_breaker-kcptun@ipv6
    systemctl start chain_breaker
}

function configuring_v2ray() {
    bash <(curl -L -s https://install.direct/go.sh)
    wget https://raw.githubusercontent.com/chaos-sudo/Cross-The-Wall/master/v2ray_default.json -O /tmp/tmp1.json
    jq .inbound.port=$V2RAY_PORT /tmp/tmp1.json >/tmp/tmp2.json
    jq .inbound.settings.clients[].id=\"$USER_ID\" /tmp/tmp2.json >/etc/v2ray/config.json
    systemctl enable v2ray
}

function optimizing_system() {
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
    ufw allow $KCPTUN_IPV4_PORT
    ufw allow $KCPTUN_IPV6_PORT
    ufw allow $UDP2RAW_IPV4_PORT
    ufw allow $UDP2RAW_IPV6_PORT
    echo "y" | ufw enable
}

specifying_parameters
configuring_v2ray
configuring_kcptun
configuring_udp2raw
configuring_services
optimizing_system

echo "v2ray uuid: $USER_ID" >/root/result.txt
echo "IPv4: $VPS_IPv4" >>/root/result.txt
echo "IPv6: $VPS_IPv6" >>/root/result.txt
echo "v2ray port: $V2RAY_PORT" >>/root/result.txt
echo "udp2raw ipv4 port: $UDP2RAW_IPV4_PORT" >>/root/result.txt
echo "udp2raw ipv6 port: $UDP2RAW_IPV6_PORT" >>/root/result.txt
echo "udp2raw password: $UDP_PASS" >>/root/result.txt
reboot
