## V2Ray 基于 Nginx 的 vmess+ws+tls 一键安装脚本

### 准备工作
* 准备一个域名，并将A记录添加好。
* [V2ray官方说明](https://www.v2ray.com/)，了解 TLS WebSocket 及 V2ray 相关信息
* 安装好 wget

### 安装/更新方式（h2 和 ws 版本已合并）
Vmess+websocket+TLS+Nginx+Website
```
wget -N --no-check-certificate -q -O install.sh "https://raw.githubusercontent.com/chinayin/v2ray_install/master/install.sh" && chmod +x install.sh && bash install.sh
```

### 安装/更新方式（v2版本 caddy版）
Vmess+websocket+TLS+Caddy+Website
```
wget -N --no-check-certificate -q -O install.sh "https://raw.githubusercontent.com/chinayin/v2ray_install/master/install_v2.sh" && bash install.sh
```

### 注意事项
* 如果你不了解脚本中各项设置的具体含义，除域名外，请使用脚本提供的默认值
* 使用本脚本需要你拥有 Linux 基础及使用经验，了解计算机网络部分知识，计算机基础操作
* 目前支持Debian 9+ / Ubuntu 18.04+ / Centos7+ ，部分Centos模板可能存在难以处理的编译问题，建议遇到编译问题时，请更换至其他系统模板
* 群主仅提供极其有限的支持，如有问题可以询问群友
* 每周日的凌晨3点，Nginx 会自动重启以配合证书的签发定时任务进行，在此期间，节点无法正常连接，预计持续时间为若干秒至两分钟

### 证书
> 如果你已经拥有了你所使用域名的证书文件，可以将 crt 和 key 文件命名为 v2ray.crt v2ray.key 放在 /data 目录下（若目录不存在请先建目录），请注意证书文件权限及证书有效期，自定义证书有效期过期后请自行续签

脚本支持自动生成 let's encrypted 证书，有效期3个月，理论上自动生成的证书支持自动续签

### 注意事项
* 推荐在纯净环境下使用本脚本，如果你是新手，请不要使用Centos系统。
* 在尝试本脚本确实可用之前，请不要将本程序应用于生产环境中。
* 该程序依赖 Nginx 实现相关功能，请使用 [LNMP](https://lnmp.org) 或其他类似携带 Nginx 脚本安装过 Nginx 的用户特别留意，使用本脚本可能会导致无法预知的错误（未测试，若存在，后续版本可能会处理本问题）。
* V2Ray 的部分功能依赖于系统时间，请确保您使用V2RAY程序的系统 UTC 时间误差在三分钟之内，时区无关。
* 本 bash 依赖于 [V2ray 官方安装脚本](https://install.direct/go.sh) 及 [acme.sh](https://github.com/Neilpang/acme.sh) 工作。
* Centos 系统用户请预先在防火墙中放行程序相关端口（默认：80，443）

### 启动方式
启动 V2ray：`systemctl start v2ray`

停止 V2ray：`systemctl stop v2ray`

启动 Nginx：`systemctl start nginx`

停止 Nginx：`systemctl stop nginx`

### 相关目录
Web 目录：`/home/wwwroot/3DCEList`

V2ray 服务端配置：`/etc/v2ray/config.json`

V2ray 客户端配置: `~/v2ray_info.inf`

Nginx 目录： `/etc/nginx`

证书文件: `/data/v2ray.key 和 /data/v2ray.crt` 请注意证书权限设置
