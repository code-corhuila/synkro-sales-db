# HU-VEN-16 credential handling: documentation handoff

Issue: [code-corhuila/synkro-docs#237](https://github.com/code-corhuila/synkro-docs/issues/237).
The earlier HU-VEN-16 hardening story is #230; use #237 for this credential fix.
Unblocks the Sales-runner portion of [HU-INF-04, #236](https://github.com/code-corhuila/synkro-docs/issues/236).
No sibling repository is edited by this change.

| Requirement → story | Verification | Implementation |
| --- | --- | --- |
| NFR-004 → HU-VEN-16 #237 | `credential-runner.test.js`: captured arguments, every supported command's output, missing configuration, unchanged failure statuses, sanitizer failure, handled termination | `deploy/migrate.sh`, `validate-state.js`, `validate-output.js`, `publish-output.js` |
| NFR-004 → HU-VEN-16 #237 | `secret-output.test.js`: literal/encoded/mixed-case/double-encoded passwords, both URI schemes, safe errors, identical environment connection passed to guard | `deploy/secret-output.js` |
| NFR-004 → HU-VEN-16 #237 | `auxiliary-credentials.test.js`: captured bootstrap/helper Docker arguments, inherited secret names, sanitized helper errors and preserved status | `deploy/ci/connection.js`, `mongosh.sh`, `start-replica-set.sh` |
| NFR-004/NFR-007 → HU-VEN-16 #237 | `credential-integration.sh`, `observe-processes.js`: real Bash/mongosh/Java cmdlines, 0700/0600 files, cleanup, authentication and unavailable-server errors | supported pinned image + shared `LIQUIBASE_COMMAND_URL` |
| NFR-007 → HU-VEN-16 #237 | rebuild, drift integration, migration-state/output, shell and sale checks: actual changesets, idempotence, drift before mutation, suppressed failures, validators/indexes/roles, rollback/reapplication | unchanged `migration-state.js` and historical changesets; secured CI helpers |

TDD evidence: commit `97b6daf` introduced the regression before the fix. Running
the preflight test against the original runner failed with `captured process arguments
must omit credentials`; the full initial run had 13 failures and 3 passes. No captured
credential values were printed. The implementation commit `21abc51` made the original
16 cases pass. Further tests cover sanitizer/termination failures and shared connection data.

Prepare a **separate synkro-docs PR** to update the traceability matrix, testing strategy,
security rules and deployment/run instructions with these tests and the candidate revision
reported at handoff. Preserve accepted ADR-010/ADR-012; clarify their operational examples
in mutable deployment documentation rather than editing immutable decisions.

Application connections target `sales` as `sales_app`, with `authSource=admin` and
`replicaSet=rs0`: the user is created in `admin`, while `sales_writer@sales` grants only
find/insert/update. The real `sale-check.sh` connection uses `authSource=admin` and
verifies those allowed operations plus denial of remove. Read-only inspection also
confirmed `authSource=admin` in the sibling `synkro-sales-api/.env.example` and its
`internal/adapter/out/persistence/mongo_integration_test.go` disposable-target check.
Administrators are used only
by migrations/bootstrap and disposable verification. This task does not assert that
the sibling application's deployed configuration has been changed.

Document owner-only ignored secret files or secret-store environment delivery,
URI-encoded credential components, inherited Docker environment names, sanitized
diagnostics, environment access by privileged administrators, and the ephemeral-container
limitation for unhandled SIGKILL. Do not log Compose/Docker configuration containing secrets.

Jordan must pin the **approved revision after manual review and merge**, not automatically
the candidate branch SHA. Remote CI, the separate documentation PR, another developer's
approval, and HU-INF-04 infrastructure integration remain pending. No PR or issue closure
is performed by this task.
