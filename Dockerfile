FROM alpine:3.22

RUN apk add --no-cache postgresql-client restic tzdata

COPY --chmod=755 backup.sh entrypoint.sh /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
