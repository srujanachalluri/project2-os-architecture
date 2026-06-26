# Project 2 — Diagnose the Failure Twice

**Tier targeted:** Hard (Normal + Medium M1 + Medium M2 + Hard memo)
**Incident(s) diagnosed:** A = Memory / sizing (OOM-kill); B = Dead service (crash loop)

## Incident A — Memory / sizing (the OOM-killer)
**Evidence:** `evidence/sample-incident.log`, `evidence/sample-dmesg.log`, `evidence/sample-ps.txt`
**Root cause (verified):** The model server (ollama / model-server.service) was OOM-killed because an FP16 7B (~13 GiB weights) plus a KV cache pre-allocated for context=32768, batch=4 (~14 GiB) did not fit RAM. systemd auto-restarted it and it was killed again — a crash loop.
**Single bottleneck:** MEMORY (a sizing failure — it never fit).
**Offending line(s):**
```
WARN  KV cache pre-allocated for context=32768, batch=4
Out of memory: Killed process 8423 (ollama) ... anon-rss:15994208kB ...
Out of memory: Killed process 8590 (ollama) ... anon-rss:15991002kB ...   (the loop)
```
In `sample-ps.txt`, ollama (PID 8423) is STAT **R**, 98.7% CPU, ~16 GB RSS — the prime memory suspect.
**Fix:** Do NOT "just restart" — it OOMs again. Quantize to Q4_K_M (~3.7 GiB) and drop context to 4K–8K, or add RAM; set a systemd `MemoryMax=` cap so it fails predictably.
**Red herrings ruled out:** `nvme0n1 I/O timeout` (it *retry-succeeded*), the USB add, the latency WARN, the coincidental apt upgrade.

## Incident B — Dead service / crash loop (different subsystem, Medium M1)
**Evidence:** `evidence/sample-journal.log`
**Root cause (verified):** `case-notes-api` cannot start because its DB login fails (bad password for "casenotes"); systemd keeps restarting it → crash loop. A credential/config failure, not code, not memory.
**Single bottleneck:** DEAD SERVICE (bad credential).
**Offending line(s):** the FIRST failure after the last clean boot —
```
Jun 19 09:02:12 ... ERROR could not connect to database: FATAL: password authentication failed for user "casenotes"
Jun 19 09:02:12 ... FATAL startup aborted: database unavailable
```
**The trap:** `systemctl status` shows "activating (auto-restart)" + a fresh "Started" line — looks like recovery. Scroll UP to the first failure; later restarts are just the loop.
**Fix:** Fix the DB credential, restart — loop stops. Add `StartLimitIntervalSec`/`StartLimitBurst` to stop infinite looping.
**Cross-check (`evidence/sample-iostat.txt`):** Capture B is I/O-bound (%iowait ~79, %util ~99, await ~142 ms); Capture A is CPU-bound (%user ~91). This column-reading is how you tell storage from CPU — neither was the cause here, which is the point.

## Adjudication — hand vs AI
**Where the AI helped:** It identified the memory/OOM and the dead service from the quoted lines and restated the fixes — a fast matching second opinion.
**Where the AI agreed (this run):** Claude did not lie — it matched my hand diagnosis on both incidents, quoted the correct lines, and correctly flagged the red herrings (the retry-succeeded I/O timeout, the USB add, the apt-upgrade timing). Its only weakness is confidence: it gives a clean answer with no hedging, so I still verified every quote against the raw evidence myself before trusting any fix. The lesson holds — the AI is a fast second opinion, not the final authority.
**Verdict:** Both incidents are as hand-diagnosed; where we disagreed I trusted the raw evidence, not the AI.

---
- **Tier targeted:** Hard
- **Root cause (verified):** A — FP16 7B + 32K/batch-4 KV exceeded RAM (OOM, crash loop). B — bad DB password → crash loop.
- **Offending line(s):** A — `Killed process 8423 (ollama) ... anon-rss:15994208kB`. B — `password authentication failed for user "casenotes"`.
- **Where the AI helped:** confirmed both headline causes from quoted lines.
- **Where the AI lied:** Nothing material this run — it agreed and quoted correctly; I still hand-verified every quote rather than taking its confidence at face value.
- **Autonomy recommendation (Hard):** AI may auto-*diagnose* (read-only) with human verification; must NOT auto-*fix*. Full reasoning in MEMO.docx.
- **What I learned:** Read the STAT column and `anon-rss` first; the OS answers its own four questions before any app log, and an OOM is arithmetic — a quant step and a smaller context separate "it crashed" from "it never fit."
- **AI usage:** Model(s)+version used: Claude (claude-opus-4-8, via Claude Code). Used for: second-opinion diagnosis of incidents A and B. Overridden when: not needed this run — I independently verified its quotes against the raw logs before acting.  Signed: Sareena Challuri
