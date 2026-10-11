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

## Local verification follow-up — 2026-10-11

The existing feature branch was reused without resetting or rewriting its six commits.
Its starting tip was `3e8ebcd10e8aa09c4d0f2a7485d5829846407250`; its unchanged
`develop` base was `ffdc24b9ce7c84b745b30bb1e85b76b07d029475`.
This follow-up clarifies the tested local runtime in README and records fresh evidence;
it does not change the previously implemented runner or historical migrations.

- Red was reproduced from commit `97b6daf` in a disposable source copy: the first
  credential regression failed with `captured process arguments must omit credentials`.
  The captured secret itself was not printed, and the source copy was removed.
- All 48 Node tests passed with zero failures, errors, cancellations or skips on
  Linux Node 22, both in the official Node image and natively in Ubuntu WSL
  (Node `22.23.3`). The six shell checks and eleven rebuild-double cases also passed.
- Bash syntax, ShellCheck with `-x -P SCRIPTDIR`, Actionlint and `git diff --check`
  passed. The direct comparison of `01_ddl/`, `02_dml/`, `03_dcl/`, `changelog/`,
  `CODEOWNERS` and the pinned runner Dockerfile against the base was empty.
- The real authenticated MongoDB rebuild, drift/suppressed-error regressions,
  credential integration and sale checks all passed against one fresh replica set.
  The ten real changesets applied successfully; repetition applied zero changes.
  Incompatible structures were rejected without repair; unexpected `createRole`
  failures and failed rollback prevented false success and reapplication.
- Real Bash, mongosh and Java process arguments were inspected during `update`,
  repeated `update`, `status --verbose`, `history` and `validate`. The observer
  confirmed no test credentials in arguments, private diagnostic permissions
  (0700 directory / 0600 files) and diagnostic cleanup. Authentication and unavailable
  server failures remained nonzero and bounded for both `update` and `status`.
- Generated administrator and application passwords contained reserved characters
  (`/:@$%+!`), were URI-encoded as data and authenticated successfully. Captured output
  from every real verification stage contained neither sentinel password nor its
  encoded representation. Failure classifications remained visible.
- Valid and invalid sale documents, exact indexes/roles, `sales_app` find/insert/update,
  denial of remove, full rollback of ten changesets and reapplication all passed.
- Windows Node 25/Git Bash executions encountered subprocess/stdin timeouts and are
  not counted as passing evidence. The complete CI-equivalent verification used
  native Linux Node 22 in WSL; README now specifies this local environment.

Disposable resources were `synkro-sales-ci-ven16-5c9ea943` (the interrupted Windows
harness) and `synkro-sales-ci-ven16-9da9d9f0` (the completed WSL sequence), each with
an exclusive network and tmpfs database storage. Cleanup verified ownership labels
before removing their containers/networks. No persistent volumes, shared networks or
preexisting databases were changed. Temporary source copies, runtime helpers and raw
diagnostic files were removed. Liquibase `4.31.1`, extension `4.29.1`, MongoDB Java
driver `3.12.14` and the runner's mongosh `2.12.0` were preserved.

Use the final pushed branch SHA reported with this follow-up as a **candidate** only.
Remote CI, a separate synkro-docs update, manual approval and HU-INF-04 infrastructure
integration remain pending; Jordan should pin the reviewed and merged revision.
