#!/bin/sh

DRY_RUN=

run_command() {
    if [ "$DRY_RUN" == "True" ]; then
        echo $@
    else
        $@
    fi
}

usage() {
    BASH_NAME=$0
    echo "usage: $BASH_NAME [OPTIONS]"
    echo "Option        GNU long option     Meaning"
    echo "-i <n>        --ipver <n>         n: 4 | 6"
    echo "-m <str>      --method <str>      str: v2ray | wireguard"
    echo "-s <str>      --speeder <str>     if this option is set, enable speeder and str: web | game"
    echo "-h            --help              show this help text and exit"

}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    usage
    exit
fi

ipvx=ipv6
method=v2ray
speeder="false"
speeder_mode=
while [ "$1" != "" ]; do
    case $1 in
        -i | --ipver )     
            shift
            ipvx=$1
            ;;
        -m | --method )         
            shift
            method=$1
            ;;
        -s | --speeder )        
            if [[ $2 != -* && $2 != "" ]]; then
                shift
                speeder_mode=$1
            fi
            speeder="true"
            ;;
        * )                     
            echo "Unknown argument: \"$1\""
            usage
            exit 1
    esac
    shift
done

if [ "$ipvx" != "ipv4" ] && [ "$ipvx" != "ipv6" ]; then
    echo "IP version is incorrect!"
    exit 1
fi

if [ "$speeder_mode" != "web" ] && [ "$speeder_mode" != "game" ]; then
    echo "speeder mode is incorrect!"
    exit 1 
fi

if [ "$method" == "wireguard" ]; then
    run_command systemctl stop v2ray.service
    run_command systemctl disable v2ray.service
    run_command wg-quick up wg0
    run_command systemctl enable wg-quick@wg0
elif [ "$method" == "v2ray" ]; then
    run_command wg-quick down wg0
    run_command systemctl disable wg-quick@wg0
    run_command systemctl start v2ray.service
    run_command systemctl enable v2ray.service
else
    echo "method is incorrect!"
    exit 1
fi

if [ "$DRY_RUN" == "True" ]; then
    echo "##### Write words below to /root/chain_breaker.conf #####"
    echo -e "CHAIN_BREAKER_IP_VERSION=$ipvx\nCHAIN_BREAKER_PROXY_METHOD=$method\nCHAIN_BREAKER_SPEEDER_ENABLE=$speeder\nCHAIN_BREAKER_SPEEDER_MODE=$speeder_mode"
    echo "#########################################################"
else
    echo -e "CHAIN_BREAKER_IP_VERSION=$ipvx\nCHAIN_BREAKER_PROXY_METHOD=$method\nCHAIN_BREAKER_SPEEDER_ENABLE=$speeder\nCHAIN_BREAKER_SPEEDER_MODE=$speeder_mode" > /root/chain_breaker.conf
fi

run_command systemctl restart udp2raw.service

if [ "$speeder" == "true" ]; then
    run_command systemctl start speeder.service
    run_command systemctl enable speeder.service
else
    run_command systemctl stop speeder.service
    run_command systemctl disable speeder.service
fi
