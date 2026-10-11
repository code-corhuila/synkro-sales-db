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

The Compose runner wraps `update` with read-only **preflight** and **postflight** checks
(`deploy/migrate.sh`). Preflight rejects an existing incompatible `sale` validator, index,
role or `sales_app` grant before the historical changesets can skip or overwrite it.
Missing domain objects are allowed before migration; `sales_app` must already exist in
`admin`, with no roles or only `sales_writer@sales`. Postflight requires the complete
approved validator, the four exact indexes plus `_id_`, the exact reader/writer privileges,
and only `sales_writer@sales` on the application user. No guard deletes or repairs drift.
Object key order, required-field order and privilege action order do not imply drift;
compound index key order does. Other structural differences fail conservatively.

The validator is read from the immutable collection changeset and tested against a
snapshot of `synkro-docs`' approved Sales model. All ten HU-VEN-05 changesets remain
byte-for-byte unchanged, including `MARK_RAN` and `failOnError: false`. The wrapper checks
the pinned Liquibase extension's exception output: a duplicate-role error (51002) is
accepted only for the corresponding preflight-validated Sales role during `update`;
unexpected suppressed failures and all suppressed rollback errors return nonzero.

Use the Compose command above for supported updates, with connection configuration in
the environment file. `update` accepts no extra flags, so a URL or changelog override cannot
make the checks inspect another target. `status`, `history`, `validate`, `rollback-count`,
`--help` and `--version` remain available. Direct Liquibase execution, another runner image
or an entrypoint override bypasses these protections; hardening those paths would require
changing historical checksums. Preflight is outside Liquibase's lock: serialize migrations
and administrator DDL changes. A suppressed error is detected after Liquibase returns;
earlier successful changesets can already have been applied. Inspect the reported failure
before retrying; never clear checksums or rewrite applied history to make it pass.

When compatible roles predate Liquibase, the historical `failOnError: false` creation
changesets remain pending after their expected duplicate errors (the pinned extension
does not record failed creations). Their definition is preserved and repeated updates
apply zero changes. Their rollback lifecycle remains with their original owner; the CI
full rollback checks start from a fresh database whose objects were created by Liquibase.

An unreachable instance fails within `serverSelectionTimeoutMS` (5 s by default in
`.env.example`) with `MongoServerSelectionError` from preflight or `MongoTimeoutException`
from Liquibase, and a non-zero exit code.

### Throwaway replica set (no infrastructure repo at hand)

```bash
export CI_MONGO_CONTAINER=synkro-sales-ci-local
export MONGODB_NETWORK=synkro-sales-ci-local
export MSYS_NO_PATHCONV=1       # Git Bash on Windows only
bash deploy/ci/start-replica-set.sh
```

It creates the administrator `admin` / `ci-admin-pw` and the service user `sales_app` /
`ci-sales-app-pw` (throwaway values, never use them elsewhere). The member host is
`$CI_MONGO_CONTAINER:27017`, the name the runner dials. Use
`MONGODB_URI=mongodb://admin:ci-admin-pw@$CI_MONGO_CONTAINER:27017` and
`MONGODB_OPTIONS=replicaSet=rs0&authSource=admin&serverSelectionTimeoutMS=5000`.

The bootstrap refuses any existing container with the selected name before making
changes. It labels the new container as disposable and stores MongoDB data in `tmpfs`;
it creates no persistent volumes and removes no container, network or volume. Defaults
remain `synkro-mongo` and `platform`; select exclusive names locally as above. Test-only
MongoDB failpoints are enabled exclusively in this throwaway instance.

### Checks

```bash
bash deploy/ci/tests/shell-regressions.sh
node --test deploy/ci/tests/*.test.js  # Node 22+, no dependencies

# Use the same isolated environment variables as the bootstrap above.
bash deploy/ci/rebuild-check.sh
bash deploy/ci/tests/integration-regressions.sh
bash deploy/ci/sale-check.sh
```

Run from the repository root with Git Bash or WSL on Windows. Database checks refuse
targets without the disposable label, `/data/db` tmpfs mount and exact CI connection.
They ignore a local `.env`: `.env.example` supplies placeholders, overridden by the CI
environment variables. The drift tests reset only this disposable database, compare
collection UUIDs, validators, documents and privileges before/after rejection, and inject
a real unexpected `createRole` failure. The sale check stops on a failed assertion or
rollback before reapplication. A command must return zero and print no `FAIL` assertion
to pass. CI starts its instance once and runs the same sequence without replacement.

If a run fails, keep the temporary instance for diagnosis and use a new exclusive name
for the next run. When finished, remove only the disposable container you created;
never remove a preexisting instance, shared network or persistent volume.

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
