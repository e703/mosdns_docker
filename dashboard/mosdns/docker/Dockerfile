FROM irinesistiana/mosdns:latest
LABEL maintainer="None"

RUN set -xe \
  && apk add --no-cache logrotate \
  && echo "0 1 * * * /usr/sbin/logrotate -v /etc/logrotate.d" >> /var/spool/cron/crontabs/root

COPY ./logrotate.conf /etc/logrotate.d/mosdns

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod a+x /entrypoint.sh

# RUN set -xe \
#   && apk add --no-cache logrotate \
#   && echo "0 1 * * * /bin/sh -c /usr/sbin/logrotate -l=syslog -d /etc/logrotate.d" >> /var/spool/cron/crontabs/root
  # && cd / \
  # && curl -LJO https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat \
  # && curl -LJO https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat \
  # && apk del curl \
  # &&  echo '0 2 * * *  wget -O /geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat'>>/var/spool/cron/crontabs/root  \
  # &&  echo '0 2 * * *  wget -O /geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat'>>/var/spool/cron/crontabs/root  \
  # && apk del curl

VOLUME /etc/mosdns
EXPOSE 6553/udp 6553/tcp
# CMD /usr/bin/mosdns start --dir /etc/mosdns

ENTRYPOINT [ "/entrypoint.sh" ]
