Project 2 — Diagnose the Failure Twice
Tier targeted: HARD (Normal + Medium M1 + Medium M2 + Hard memo)
Author: Sareena Challuri

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
