// Permission cases (case 5). Run with mongosh authenticated as sales_app,
// against the `sales` database. Prints PASS/FAIL and exits non-zero on failure.
let failed = 0;
const report = (ok, name, detail) => { if (!ok) failed++; print(`${ok ? "PASS" : "FAIL"} ${name}${detail ? " -> " + detail : ""}`); };
const attempt = (name, fn, expectDenied) => {
  try { fn(); report(!expectDenied, name, expectDenied ? "was ALLOWED" : "allowed"); }
  catch (e) { report(expectDenied && e.code === 13, name, `code ${e.code}: ${e.message.slice(0, 110)}`); }
};
const U = "00000000-0000-4000-8000-0000000000aa";
const doc = { _id: U, customerId: U, createdBy: U, date: new Date(), totalCents: NumberLong("1"), active: true,
  idempotencyKey: "perm-check-key",
  details: [{ detailId: U, productId: U, quantity: NumberInt(1), unitPriceCents: NumberLong("1"), subtotalCents: NumberLong("1"), active: true }] };
attempt("case 5a: sales_app can insert", () => db.sale.insertOne(doc), false);
attempt("case 5b: sales_app can find", () => { if (db.sale.countDocuments({ _id: U }) !== 1) throw new Error("not found"); }, false);
attempt("case 5c: sales_app can update", () => db.sale.updateOne({ _id: U }, { $set: { active: false } }), false);
attempt("case 5d: sales_app cannot deleteOne", () => db.sale.deleteOne({ _id: U }), true);
attempt("case 5e: sales_app cannot deleteMany", () => db.sale.deleteMany({}), true);
attempt("case 5f: sales_app cannot read another database", () => db.getSiblingDB("other").x.findOne(), true);
attempt("case 5g: sales_app cannot write another database", () => db.getSiblingDB("other").x.insertOne({ a: 1 }), true);
quit(failed ? 1 : 0);
