# Commercial number

Detailed procedures and delivery notes moved from the repository README at
[source 70c2c5d](https://github.com/code-corhuila/synkro-sales-db/blob/70c2c5d603e0083566918144f5f0b63ad4108d7a/README.md).
Recorded execution results retain their original scope; moving them does not
constitute a new execution or certify a different revision.

Run commands from the repository root unless a step explicitly changes directory.

## Commercial sale number (HU-VEN-20)

Four additive changesets (`sale-011` … `sale-014`) add the human reference of a sale,
`VEN-YYYY-NNNNNN` (for example `VEN-2026-000001`). It is a commercial receipt reference,
not a fiscal invoice number. The sale `_id` UUID stays the internal identity.

| Changeset | Object |
|---|---|
| `sale-011` | `collMod` on `sale`: optional `commercialNumber` (`^VEN-[1-9][0-9]{3}-[0-9]{6}$`). Optional, so stored sales stay valid and nothing is rewritten. |
| `sale-012` | Collection `sale_counter`, one document per year (`_id` `VEN-2026`, `seq` long 0…999999). The validator makes the six-digit ceiling a database rule. |
| `sale-013` | Unique partial index `uq_sale_commercial_number` (only documents that have the field). |
| `sale-014` | `sales_writer` also gets `find/insert/update` on `sale_counter` (no `remove`). |

The Sales API advances the counter atomically (`findOneAndUpdate` with `$inc`), so concurrent
sales receive distinct numbers. A number is consumed even if the following insert is lost, so
**gaps are possible**; only uniqueness and immutability are guaranteed. The year is the
Colombian calendar year (UTC-5, no daylight saving) of the sale date.

Deployment order: apply this migration first, then the API that writes the field. Applying it
does not touch existing sales. The earlier validator and the previous role privileges are
restored by `rollback-count`. The guards accept the previous state before the migration and
require the new state afterwards.
