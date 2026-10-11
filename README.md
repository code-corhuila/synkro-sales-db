# synkro-sales-db

> sales bounded context: database (schema, seeds, migrations)

Part of the **SynkroTech SAS Sales Management System** — organization `code-corhuila`.
Governance and documentation live in [`synkro-docs`](https://github.com/code-corhuila/synkro-docs).

## Branching

Three permanent branches. **None of them accepts a direct commit** — you enter through a child
branch and leave through a Pull Request.

```
develop  <--PR--  feat/... fix/... chore/...
qa       <--PR--  qa/...
main     <--PR--  release/...  hotfix/...
```

Promotion happens **by re-application** (`git cherry-pick -x`), never by merging one permanent
branch into another: `merge develop -> qa` and `merge qa -> main` do not exist in this model.

`main` requires **1 approval from `ariel5253`**. On `develop` and `qa` the team sets its own review
rule.

Full policy: `00-governance/branching-policy.md` in `synkro-docs`.

## Migrations (Liquibase over MongoDB)

This repository owns the migrations of the `sales` database (ADR-010). The MongoDB instance
itself (a single-node replica set `rs0`) is **not** defined here: it belongs to
`synkro-infra-mongo`. This repository only ships the runner.

```
changelog/changelog-master.yaml   # single entry point
01_ddl/  00_collections  01_validators  02_indexes  03_views
02_dml/  00_inserts  01_updates  02_deletes  03_upserts  04_patches
03_dcl/  00_roles
deploy/  liquibase.Dockerfile, compose.yml   # the runner only
```

Each family folder has its own `changelog.yaml`; `01_ddl/`, `02_dml/` and `03_dcl/` have an
aggregator that includes their sub-folders in order. There is no folder for foreign keys: MongoDB
has none. The families are empty for now; the `sale` collection and its validator arrive with
HU-VEN-05.

### Run the migrations locally

Prerequisites: Docker, and a reachable MongoDB replica set (for example the one started by
`synkro-infra-mongo`) on the Docker network `platform`.

```bash
cp .env.example .env            # then fill in the placeholders; .env is git-ignored
docker network create platform  # only if it does not exist yet

# apply (Liquibase update)
docker compose --env-file .env -f deploy/compose.yml run --rm --build sales-db-migrate

# pending changesets / history
docker compose --env-file .env -f deploy/compose.yml run --rm sales-db-migrate status --verbose
docker compose --env-file .env -f deploy/compose.yml run --rm sales-db-migrate history
```

Running `update` a second time applies zero changesets. Liquibase keeps its history in the
`DATABASECHANGELOG` and `DATABASECHANGELOGLOCK` collections of the target database; those two are
expected in an otherwise empty database.

An unreachable instance fails within `serverSelectionTimeoutMS` (5 s by default in
`.env.example`) with a `MongoTimeoutException` and a non-zero exit code.

### Throwaway replica set (no infrastructure repo at hand)

```bash
docker network create platform
docker run -d --name synkro-mongo --network platform mongo:7.0 --replSet rs0 --bind_ip_all
docker exec synkro-mongo mongosh --quiet --eval \
  'rs.initiate({_id:"rs0",members:[{_id:0,host:"synkro-mongo:27017"}]})'
```

The member host must be `synkro-mongo:27017`, the name the runner dials; the default (the
container ID) is not resolvable from another container. This instance has no access control, so
use `MONGODB_URI=mongodb://synkro-mongo:27017`.
