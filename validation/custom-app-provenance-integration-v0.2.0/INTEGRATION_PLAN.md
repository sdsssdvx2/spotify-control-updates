Validation-only acceptance contract:

1. Build exact source-topology candidate from pinned validated parent.
2. Import exact custom-app provenance core by pinned blob/commit identity.
3. Import exact Marketplace native-refresh contract by pinned blob/commit identity.
4. Observe provenance only for current safe local custom-app lifecycle rows.
5. Persist provenance under a distinct `custom_app_provenance` state root; do not reuse or overwrite `lifecycle` or Marketplace identity ledger keys.
6. Provenance never grants mutation/install/update authority. Every generic provenance row remains deny-by-default.
7. Source changes, weak package-only evidence, `.git` indirection/reparse, missing/ambiguous lifecycle all fail closed.
8. Marketplace extension/theme/snippet native-refresh classification remains informational; direct Addon Manager mutation is always denied.
9. Preserve Tagify exact registry source gate and existing protected persistence backup/restore transaction.
10. Preserve Splitify, Star Ratings, and SC Cover Ambience protections.
11. Parse under Windows PowerShell 5.1; run full Addon Manager SelfTest plus provenance/native-refresh selftests.
12. Prove deterministic candidate output and production/parent immutability.
