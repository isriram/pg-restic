# Alpine's stable repos lag behind restic releases, so take the static binary from the official image
FROM restic/restic:0.19.1 AS restic

FROM alpine:3.24

# "postgresql-client" is a virtual package that several versions provide, so name the major explicitly.
# Exact versions (=18.6-r0) aren't pinned because Alpine drops old patch releases from its repos.
RUN apk add --no-cache postgresql18-client tzdata

COPY --from=restic /usr/bin/restic /usr/bin/restic
COPY --chmod=755 backup.sh entrypoint.sh /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
