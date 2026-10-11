# Migration runner: pinned Liquibase + the MongoDB extension AND the Java driver.
# Installing only the extension fails with "Driver class was not specified."
FROM mongo:7.0 AS mongo-client
FROM liquibase/liquibase:4.31.1

# mongosh is self-contained and uses the same Ubuntu 22.04 runtime libraries.
COPY --from=mongo-client /usr/bin/mongosh /usr/local/bin/mongosh

# `lpm add <name>` alone installs whatever is newest, so both are pinned.
# 4.29.1 is the newest liquibase-mongodb lpm offers for core 4.31.x.
RUN lpm add liquibase-mongodb@4.29.1 mongodb@3.12.14 --global

ENTRYPOINT ["bash", "/liquibase/changelog-root/deploy/migrate.sh"]
