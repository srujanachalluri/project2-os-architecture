# Memo: How Much Diagnostic Autonomy to Grant an AIOps Assistant
**To:** IT lead, Lutheran relief organization
**From:** Sareena Challuri
**Re:** Whether to let an AI automatically diagnose and fix the rotation incidents

## Recommendation in one line
Let the AI **suggest, never execute.** Read-only *diagnostic* autonomy with mandatory human verification; **zero** auto-*fix* authority.

## Per-incident judgment
**Incident A — OOM / sizing.** Auto-diagnose: YES (read-only triage is safe). Auto-fix: **NO.** The reflex "restart" is exactly wrong — the box re-OOMs and crash-loops (we saw the second kill, PID 8590). The real fix (requantize, shrink context, add RAM, set `MemoryMax`) is a change-management decision.
**Incident B — bad credential.** Auto-diagnose: YES. Auto-fix: **NO.** It touches a DB secret — a security action. An AI "auto-correcting" auth could rotate a secret, lock the `casenotes` account, or break other clients.

## Worst case if it auto-fixed wrong
A restart loop masks the sizing fault, so the model server keeps OOM-ing and starves postgres on the same box — risking the **donor database** and case records. A wrong credential rotation takes case-notes offline for every volunteer at once. Both dwarf the few minutes a human check adds.

## Textbook grounding
- **§2.2–2.3 (four questions; STAT and `anon-rss`):** diagnosis comes from the OS's own evidence, read by a human, before any fix.
- **§2.7 (sizing rules):** the OOM is arithmetic — weights + KV + overhead — and the fix follows from the math, not a restart.

## Cost reasoning
A cloud LLM second-opinion costs cents per incident; a wrong auto-fix that corrupts donor data or downs case-notes costs overtime, restore time, and trust. The local GPU is a sunk cost and keeps donor data in the building, so use it for advisory triage. **Net: the AI earns its keep as a read-only assistant that drafts the diagnosis and the math; a human approves every change.** Autonomy granted: *suggest-only.*

Signed: Sareena Challuri
