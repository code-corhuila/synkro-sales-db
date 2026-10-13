// Acceptance and rejection cases for the `sale` collection. Run with mongosh
// against the `sales` database as the administrator. Prints PASS/FAIL per case
// and exits non-zero when any case fails. Used by sale-check.sh.
const UUID = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const line = (n, over = {}) => ({
  detailId: UUID(100 + n), productId: UUID(200 + n), quantity: NumberInt(2),
  unitPriceCents: NumberLong("500"), subtotalCents: NumberLong("1000"), active: true, ...over,
});
let seq = 0;
const sale = (over = {}, lines = [line(1)]) => ({
  _id: UUID(++seq), customerId: UUID(900), createdBy: UUID(901), date: new Date(),
  totalCents: NumberLong("1000"), active: true, idempotencyKey: `key-${seq}-${Date.now()}`,
  details: lines, ...over,
});
const many = (k) => Array.from({ length: k }, (_, i) => line(i + 1));

let failed = 0;
const report = (ok, name, detail) => {
  if (!ok) failed++;
  print(`${ok ? "PASS" : "FAIL"} ${name}${detail ? " -> " + detail : ""}`);
};
const accepts = (name, doc) => {
  try { db.sale.insertOne(doc); report(true, name); } catch (e) { report(false, name, e.message.slice(0, 110)); }
};
const rejects = (name, doc, code = 121) => {
  try { db.sale.insertOne(doc); report(false, name, "document was ACCEPTED"); }
  catch (e) { report(e.code === code, name, `code ${e.code}: ${e.message.slice(0, 110)}`); }
};

const phase = process.env.PHASE || "all";

if (phase === "structure") {
  const info = db.getCollectionInfos({ name: "sale" })[0];
  report(!!info, "case 1a: collection sale exists");
  report(info && info.options.validationLevel === "strict" && info.options.validationAction === "error",
    "case 1b: validationLevel strict, validationAction error");
  const idx = db.sale.getIndexes().map((i) => i.name).sort().join(",");
  const want = ["_id_", "idx_sale_created_by_date", "idx_sale_customer_id_date", "idx_sale_date", "uq_sale_idempotency_key"].join(",");
  report(idx === want, "case 1c: indexes", idx);
  const u = db.sale.getIndexes().find((i) => i.name === "uq_sale_idempotency_key");
  report(u && u.unique === true, "case 1d: uq_sale_idempotency_key is unique");
  const roles = db.getRoles({ rolesInfo: 1, showPrivileges: true }).roles.map((r) => r.role).sort().join(",");
  report(roles === "sales_reader,sales_writer", "case 1e: roles exist", roles);
  const user = db.getSiblingDB("admin").getUser("sales_app");
  report(user && user.roles.some((r) => r.role === "sales_writer" && r.db === "sales"),
    "case 1f: sales_writer granted to sales_app");
  quit(failed ? 1 : 0);
}
if (phase === "absent") {
  const cols = db.getCollectionNames().filter((n) => !n.startsWith("DATABASECHANGELOG"));
  const roles = db.getRoles().roles.length;
  const user = db.getSiblingDB("admin").getUser("sales_app");
  report(cols.length === 0 && roles === 0 && user && user.roles.length === 0,
    "rollback: no collection, no role or grant left", `collections=${cols} roles=${roles}`);
  quit(failed ? 1 : 0);
}

accepts("case 2a: valid sale, 1 line", sale());
accepts("case 2b: valid sale, 100 lines", sale({}, many(100)));

rejects("case 3a: extra field at document level", sale({ extra: 1 }));
rejects("case 3b: extra field inside a line", sale({}, [line(1, { extra: 1 })]));
for (const f of ["_id", "customerId", "createdBy"]) rejects(`case 3c: non-UUID ${f}`, sale({ [f]: "not-a-uuid" }));
rejects("case 3c: non-UUID line productId", sale({}, [line(1, { productId: "nope" })]));
rejects("case 3c: non-UUID line detailId", sale({}, [line(1, { detailId: "nope" })]));
rejects("case 3d: totalCents as string", sale({ totalCents: "1000" }));
rejects("case 3d: active as string", sale({ active: "true" }));
rejects("case 3e: details with 0 items", sale({}, []));
rejects("case 3f: details with 101 items", sale({}, many(101)));
rejects("case 3g: quantity 0", sale({}, [line(1, { quantity: NumberInt(0) })]));
rejects("case 3g: unitPriceCents 0", sale({}, [line(1, { unitPriceCents: NumberLong("0") })]));
rejects("case 3g: subtotalCents 0", sale({}, [line(1, { subtotalCents: NumberLong("0") })]));

const dup = sale();
accepts("case 4a: first sale with a key", dup);
rejects("case 4b: duplicate idempotencyKey", sale({ idempotencyKey: dup.idempotencyKey }), 11000);

quit(failed ? 1 : 0);
