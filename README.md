# 翻墙VPS部署脚本
## 环境
Ubuntu 18.04
## 所用工具
[UDPspeeder](https://https://github.com/wangyu-/UDPspeeder), [udp2raw](https://github.com/wangyu-/udp2raw-tunnel), [v2ray](https://github.com/v2ray/v2ray-core), [wireguard](https://www.wireguard.com)
## 实现功能

||客户端|🧱|服务器|
|:-------------:|-------------:|:-------------:|:-------------|
|1|v2ray→UDPspeeder→udp2raw➡️| 🧱 |➡️udp2raw→UDPspeeder→v2ray|
|2|wireguard→UDPspeeder→udp2raw➡️| 🧱 |➡️udp2raw→UDPspeeder→wireguard|
|3|v2ray→udp2raw➡️| 🧱 |➡️udp2raw→v2ray|
|4|wireguard→udp2raw➡️| 🧱 |➡️udp2raw→wireguard|

### 使用方法
在VPS网站上创建服务器时，添加下列语句到自定义配置脚本中，或手动运行：
```bash
apt update
apt install wget -y
wget https://raw.githubusercontent.com/chaos-sudo/Cross-The-Wall/master/build.sh -O /tmp/build.sh
bash /tmp/build.sh
```