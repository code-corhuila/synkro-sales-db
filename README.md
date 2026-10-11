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
has none. The `sale` collection (with its validator), its four indexes, the roles `sales_reader` and
`sales_writer` and the grant to `sales_app` live in `01_ddl/00_collections`, `01_ddl/02_indexes` and
`03_dcl/00_roles`. The other families are still empty. A later validator change is a new `collMod`
changeset under `01_ddl/01_validators/`, never an edit of the one that created the collection.

Every changeset can be re-run on its own and declares its reversal inline (`rollback:`). The grant
fails when `sales_app` does not exist: the instance's bootstrap (`synkro-infra-mongo`) creates it.
`subtotalCents = quantity * unitPriceCents` and `totalCents = sum(subtotalCents)` are **not** checked
here: the validator only checks types and ranges, `synkro-sales-api` enforces the arithmetic.

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
deploy/ci/start-replica-set.sh   # rs0 on the `platform` network, access control on
```

It creates the administrator `admin` / `ci-admin-pw` and the service user `sales_app` /
`ci-sales-app-pw` (throwaway values, never use them elsewhere). The member host is
`synkro-mongo:27017`, the name the runner dials. Use
`MONGODB_URI=mongodb://admin:ci-admin-pw@synkro-mongo:27017` and
`MONGODB_OPTIONS=replicaSet=rs0&authSource=admin&serverSelectionTimeoutMS=5000`.

### Checks

```bash
deploy/ci/rebuild-check.sh   # apply, apply again (zero changes), invalid connection fails fast
deploy/ci/start-replica-set.sh && deploy/ci/sale-check.sh   # sale validator, indexes, permissions, full rollback and re-apply
```

### Sample sale documents (manual checks)

Connect as the administrator (`mongosh "mongodb://admin:ci-admin-pw@localhost:27017/sales?authSource=admin"`
inside the container). Numbers must be typed: `totalCents`, `unitPriceCents` and `subtotalCents` are
`long`, `quantity` is `int`, `date` is a date.

Valid (accepted):

```js
db.sale.insertOne({
  _id: "5f0c1e3a-8b7d-4c21-9a55-0d1e2f3a4b5c",
  customerId: "a1b2c3d4-0000-4000-8000-000000000001",
  createdBy: "a1b2c3d4-0000-4000-8000-000000000002",
  date: new Date(), totalCents: Long("1000"), active: true, idempotencyKey: "retry-key-0001",
  details: [{ detailId: "a1b2c3d4-0000-4000-8000-000000000003", productId: "a1b2c3d4-0000-4000-8000-000000000004",
              quantity: Int32(2), unitPriceCents: Long("500"), subtotalCents: Long("1000"), active: true }]
})
```

Invalid (each fails with `Document failed validation`, code 121): an undeclared field (`extra: 1`) at
the document or line level; a non-UUID `_id`, `customerId`, `createdBy`, `productId` or `detailId`
(for example `"not-a-uuid"`); `totalCents: "1000"` or `active: "true"`; `details: []`; 101 lines;
`quantity: Int32(0)`, `unitPriceCents: Long("0")` or `subtotalCents: Long("0")`. Inserting a second
sale with the same `idempotencyKey` fails with code 11000 on `uq_sale_idempotency_key`.
