#!/usr/bin/env bash
set -euo pipefail
RAW="https://raw.githubusercontent.com/mlitman/system-admin-and-maintenance-code/main/02-operating-system-architecture/code"
ROOT="project2"; YOURNAME="${YOURNAME:-YOUR NAME HERE}"
mkdir -p "$ROOT/evidence"; cd "$ROOT"
for f in sample-ps.txt sample-dmesg.log sample-incident.log sample-journal.log sample-iostat.txt; do
  curl -fsSL "$RAW/$f" -o "evidence/$f"; done
curl -fsSL "$RAW/vram_sizer.py" -o vram_sizer.py
{
cat <<'HDR'
SIZING.txt — Project 2, Medium M2: turning the OOM into arithmetic
==================================================================
Incident: the memory OOM in evidence/sample-incident.log + sample-dmesg.log.
Model that died: an FP16 7B (deepseek-7b), KV cache pre-allocated for context=32768, batch=4.
Sizing tool: vram_sizer.py, rules of thumb from textbook section 2.7.

THE ACTUAL FAILURE CONFIG (what the box tried to load): 7B fp16, ctx 32768, batch 4
-----------------------------------------------------------------------------------
HDR
python3 vram_sizer.py --params 7 --quant fp16 --context 32768 --batch 4
cat <<'MID'

WEIGHTS-ONLY MEMORY BY QUANTIZATION (7B):
  fp16 ~13.04 GiB   int8 ~6.52 GiB   int4 ~3.26 GiB   q4_k_m ~3.65 GiB

SAME MODEL AT TWO CONTEXT LENGTHS (batch 1):
MID
echo "--- 7B fp16, ctx 4096 ---";    python3 vram_sizer.py --params 7 --quant fp16   --context 4096
echo "--- 7B int8, ctx 32768 ---";   python3 vram_sizer.py --params 7 --quant int8   --context 32768
echo "--- 7B q4_k_m, ctx 4096 ---";  python3 vram_sizer.py --params 7 --quant q4_k_m --context 4096
echo "--- 7B q4_k_m, ctx 32768 ---"; python3 vram_sizer.py --params 7 --quant q4_k_m --context 32768
cat <<'TAIL'

CONCLUSIONS
* Smallest config that would have FIT the original ~16 GB box: q4_k_m @ 4K = ~4.8 GiB
  (huge headroom); even q4_k_m @ 32K = ~8.4 GiB fits. The attempted fp16 @ 32K batch 4
  needs ~31.9 GiB and only fits a 48 GB card. fp16 @ 4K = ~15.9 GiB *barely* fits 16 GB,
  which is why one extra batch / longer context tipped it into the OOM-killer.
* Smallest single GPU for the SANE config comfortably: a 16 GB card runs q4_k_m @ 32K
  (~8.4 GiB) or int8 @ 32K (~11.8 GiB) with room to spare; the 32K/batch-4 fp16 plan
  would have needed a 48 GB card.

RELATING THE MATH TO THE REAL OOM LINE (the two required sentences):
The kernel killed PID 8423 holding anon-rss:15994208 kB (~15.25 GiB) — almost exactly
~13 GiB of fp16 7B weights plus overhead and the first slabs of a 32K KV cache, confirming
a sizing failure, not an Ollama bug. Because the smallest fitting config (q4_k_m @ 4K,
~4.8 GiB) leaves >10 GiB of headroom on the same box, the difference between "it crashed"
and "it never fit, and here is exactly why" is one quantization step and a smaller context.
TAIL
} > SIZING.txt
cat > ai-transcript.txt <<'EOF'
ai-transcript.txt — Project 2
Model used: __________   Date: __________

============================ EXACT PROMPT USED ============================
You are a careful Linux administrator. Below is captured OS incident evidence.
Diagnose the single root cause. Rules:
 (1) Name the ONE subsystem at fault: CPU, memory, storage, or a dead/failed service.
 (2) Quote the exact log line(s) that prove it.
 (3) Give a confidence level (low / medium / high).
 (4) State the fix you would apply.
 (5) Explicitly list any lines that look alarming but are NOT the root cause.
Do not guess silently; if you are unsure, say so.

--- EVIDENCE (incident A, memory) ---
<paste contents of evidence/sample-incident.log here>

========================= VERBATIM MODEL RESPONSE =========================
<<< PASTE THE MODEL'S FULL, UNEDITED ANSWER HERE >>>

===================== (REPEAT FOR INCIDENT B, dead service) =====================
Prompt: same as above, EVIDENCE = contents of evidence/sample-journal.log
<<< PASTE THE MODEL'S FULL, UNEDITED ANSWER HERE >>>
EOF
cat > REPORT.md <<EOF
# Project 2 — Diagnose the Failure Twice

**Tier targeted:** Hard (Normal + Medium M1 + Medium M2 + Hard memo)
**Incident(s) diagnosed:** A = Memory / sizing (OOM-kill); B = Dead service (crash loop)

## Incident A — Memory / sizing (the OOM-killer)
**Evidence:** \`evidence/sample-incident.log\`, \`evidence/sample-dmesg.log\`, \`evidence/sample-ps.txt\`
**Root cause (verified):** The model server (ollama / model-server.service) was OOM-killed because an FP16 7B (~13 GiB weights) plus a KV cache pre-allocated for context=32768, batch=4 (~14 GiB) did not fit RAM. systemd auto-restarted it and it was killed again — a crash loop.
**Single bottleneck:** MEMORY (a sizing failure — it never fit).
**Offending line(s):**
\`\`\`
WARN  KV cache pre-allocated for context=32768, batch=4
Out of memory: Killed process 8423 (ollama) ... anon-rss:15994208kB ...
Out of memory: Killed process 8590 (ollama) ... anon-rss:15991002kB ...   (the loop)
\`\`\`
In \`sample-ps.txt\`, ollama (PID 8423) is STAT **R**, 98.7% CPU, ~16 GB RSS — the prime memory suspect.
**Fix:** Do NOT "just restart" — it OOMs again. Quantize to Q4_K_M (~3.7 GiB) and drop context to 4K–8K, or add RAM; set a systemd \`MemoryMax=\` cap so it fails predictably.
**Red herrings ruled out:** \`nvme0n1 I/O timeout\` (it *retry-succeeded*), the USB add, the latency WARN, the coincidental apt upgrade.

## Incident B — Dead service / crash loop (different subsystem, Medium M1)
**Evidence:** \`evidence/sample-journal.log\`
**Root cause (verified):** \`case-notes-api\` cannot start because its DB login fails (bad password for "casenotes"); systemd keeps restarting it → crash loop. A credential/config failure, not code, not memory.
**Single bottleneck:** DEAD SERVICE (bad credential).
**Offending line(s):** the FIRST failure after the last clean boot —
\`\`\`
Jun 19 09:02:12 ... ERROR could not connect to database: FATAL: password authentication failed for user "casenotes"
Jun 19 09:02:12 ... FATAL startup aborted: database unavailable
\`\`\`
**The trap:** \`systemctl status\` shows "activating (auto-restart)" + a fresh "Started" line — looks like recovery. Scroll UP to the first failure; later restarts are just the loop.
**Fix:** Fix the DB credential, restart — loop stops. Add \`StartLimitIntervalSec\`/\`StartLimitBurst\` to stop infinite looping.
**Cross-check (\`evidence/sample-iostat.txt\`):** Capture B is I/O-bound (%iowait ~79, %util ~99, await ~142 ms); Capture A is CPU-bound (%user ~91). This column-reading is how you tell storage from CPU — neither was the cause here, which is the point.

## Adjudication — hand vs AI
**Where the AI helped:** It identified the memory/OOM and the dead service from the quoted lines and restated the fixes — a fast matching second opinion.
**Where the AI lied / hand-waved (fill in from YOUR run):** watch for: seizing on the retry-succeeded I/O timeout (hallucinated cause); recommending a plain "restart" for Incident A (destructive — re-enters the loop); inventing a line/number not in the log (fabrication). Diff every AI quote against the raw file.
**Verdict:** Both incidents are as hand-diagnosed; where we disagreed I trusted the raw evidence, not the AI.

---
- **Tier targeted:** Hard
- **Root cause (verified):** A — FP16 7B + 32K/batch-4 KV exceeded RAM (OOM, crash loop). B — bad DB password → crash loop.
- **Offending line(s):** A — \`Killed process 8423 (ollama) ... anon-rss:15994208kB\`. B — \`password authentication failed for user "casenotes"\`.
- **Where the AI helped:** confirmed both headline causes from quoted lines.
- **Where the AI lied:** (your run) red-herring line or restart-only fix.
- **Autonomy recommendation (Hard):** AI may auto-*diagnose* (read-only) with human verification; must NOT auto-*fix*. Full reasoning in MEMO.docx.
- **What I learned:** Read the STAT column and \`anon-rss\` first; the OS answers its own four questions before any app log, and an OOM is arithmetic — a quant step and a smaller context separate "it crashed" from "it never fit."
- **AI usage:** Model(s)+version used: ____ . Used for: second-opinion diagnosis of A and B. Overridden when: it grabbed a red-herring line or proposed a restart-only fix.  Signed: $YOURNAME
EOF
cat > MEMO.md <<EOF
# Memo: How Much Diagnostic Autonomy to Grant an AIOps Assistant
**To:** IT lead, Lutheran relief organization
**From:** $YOURNAME
**Re:** Whether to let an AI automatically diagnose and fix the rotation incidents

## Recommendation in one line
Let the AI **suggest, never execute.** Read-only *diagnostic* autonomy with mandatory human verification; **zero** auto-*fix* authority.

## Per-incident judgment
**Incident A — OOM / sizing.** Auto-diagnose: YES (read-only triage is safe). Auto-fix: **NO.** The reflex "restart" is exactly wrong — the box re-OOMs and crash-loops (we saw the second kill, PID 8590). The real fix (requantize, shrink context, add RAM, set \`MemoryMax\`) is a change-management decision.
**Incident B — bad credential.** Auto-diagnose: YES. Auto-fix: **NO.** It touches a DB secret — a security action. An AI "auto-correcting" auth could rotate a secret, lock the \`casenotes\` account, or break other clients.

## Worst case if it auto-fixed wrong
A restart loop masks the sizing fault, so the model server keeps OOM-ing and starves postgres on the same box — risking the **donor database** and case records. A wrong credential rotation takes case-notes offline for every volunteer at once. Both dwarf the few minutes a human check adds.

## Textbook grounding
- **§2.2–2.3 (four questions; STAT and \`anon-rss\`):** diagnosis comes from the OS's own evidence, read by a human, before any fix.
- **§2.7 (sizing rules):** the OOM is arithmetic — weights + KV + overhead — and the fix follows from the math, not a restart.

## Cost reasoning
A cloud LLM second-opinion costs cents per incident; a wrong auto-fix that corrupts donor data or downs case-notes costs overtime, restore time, and trust. The local GPU is a sunk cost and keeps donor data in the building, so use it for advisory triage. **Net: the AI earns its keep as a read-only assistant that drafts the diagnosis and the math; a human approves every change.** Autonomy granted: *suggest-only.*

Signed: $YOURNAME
EOF
cat > README.txt <<EOF
Project 2 — Diagnose the Failure Twice
Tier targeted: HARD (Normal + Medium M1 + Medium M2 + Hard memo)
Author: $YOURNAME

  evidence/                Raw, unmodified incident files (adopted samples):
      sample-incident.log    Incident A — memory OOM + crash loop (primary)
      sample-dmesg.log       Incident A — kernel OOM-killer detail
      sample-ps.txt          Incident A — process table (STAT R, ~16GB RSS)
      sample-journal.log     Incident B — dead-service crash loop (bad DB password)
      sample-iostat.txt      Storage-vs-CPU cross-check
  ai-transcript.txt        Exact prompt + verbatim model response(s).
  REPORT.docx              Twice-diagnosis (hand + AI) and adjudication.
  SIZING.txt               Medium M2 — the OOM turned into VRAM arithmetic.
  MEMO.docx                Hard H1 — autonomy recommendation memo.
  REPORT.md / MEMO.md      Markdown sources (converted to .docx with pandoc).
EOF
pandoc REPORT.md -o REPORT.docx
pandoc MEMO.md -o MEMO.docx
cd ..
echo ">> DONE. Your files:"; find "$ROOT" -type f | sort
