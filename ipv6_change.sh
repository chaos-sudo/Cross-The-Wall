#!/bin/bash

function get_hex_2 {
    echo $(openssl rand -hex 2)
}

network_interface=$(ip addr | awk '/state UP/ {print $2}' | sed 's/.$//')
random_part="$(get_hex_2):$(get_hex_2):$(get_hex_2):$(get_hex_2)"
re='inet6 ([a-f0-9]+:[a-f0-9]+:[a-f0-9]+:[a-f0-9]+)';
[[ $(ifconfig $network_interface) =~ $re ]];
ipv6_prefix=${BASH_REMATCH[1]}
random_ipv6="$ipv6_prefix:$random_part"

if hash netplan 2>/dev/null; then
    cat <<EOF >/etc/netplan/10-$network_interface.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $network_interface:
      dhcp4: yes
      addresses: ['$random_ipv6/64']
EOF
#    sed "s|\(addresses: \).*|\1\[\'$random_ipv6\/64\'\]|" /etc/netplan/10-$network_interface.yaml
  netplan apply
else
  echo "no netplan found"
fi

sed -i'.orig' "s|\(^IPv6: \).*|\1$random_ipv6|" /root/result.txt
echo $random_ipv6
