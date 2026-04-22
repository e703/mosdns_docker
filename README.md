# mosdns_docker

unofficial mosdns docker image 

## Dashboard

详情见 /dashboard/README.md
- 将 [vector + loki 实现 mosdns 数据看板](https://icyleaf.com/2023/08/using-vector-transform-mosdns-logging-to-grafana-via-loki/#prometheus) 整合为了 docker-compose,方便部署.
- 本版本调整内容如下：
  - 增加adguardhome做为DNS内部接入服务（53 TCP/UDP）；上游为MOSDNS（6553 TCP/UDP）；
  - adguardhome采用官方镜像，添加我常用的国内过滤规则。
  - 全部使用Docker容器部署。
  - 更新时间：2024年11月5日  
- 
为升级重新适配MOSDNS V5.3.4 版本，决定重新适配并对相关文件进行细化说明。
  -更新时间：2026年4月22日开始
  -尚未完成，进行中……
