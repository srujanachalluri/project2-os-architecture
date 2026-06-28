#!/usr/bin/env python3
"""vram_sizer.py - hand-checkable memory sizing for a local LLM
"""
import argparse

# Approx bytes per weight by precision (the sec 2.7 rules of thumb).
BYTES_PER_WEIGHT = {
    "fp16": 2.0, "bf16": 2.0,
    "int8": 1.0, "fp8": 1.0, "q8": 1.0,
    "int4": 0.5, "q4": 0.5, "q4_k_m": 0.56,  # Q4_K_M ~4.5 bits/weight
}

# Very rough per-model KV-cache cost: bytes per token per billion params.
# A planning heuristic, NOT exact (depends on layers/heads/GQA). Use to show
# that long context can rival or exceed the weights, per the fact brief.
#
# The exact per-token KV-cache cost of a model is:
#   KV bytes/token = 2 (K and V) * layers * kv_dim * bytes_per_elem
# where kv_dim = (kv_heads * head_dim) is the *grouped* KV width under GQA.
# For a 7B/8B-class GQA model (e.g. Llama-3-8B / Mistral-7B) with an fp16 KV
# cache: 2 * 32 layers * 1024 kv_dim * 2 bytes = 131,072 bytes/token. Divided
# by ~8B params that is ~16,384 bytes/token per 1B params -- our heuristic.
# Sanity check: 7B @ 4K -> ~0.44 GiB; 7B @ 32K -> ~3.5 GiB (rivals the
# weights at long context, exactly the point of sec 2.7).
KV_BYTES_PER_TOKEN_PER_B = 16384.0  # ~16 KB/token per 1B params (fp16 KV, GQA)


def gib(nbytes: float) -> float:
    return nbytes / (1024 ** 3)


def main() -> None:
    p = argparse.ArgumentParser(description="LLM memory sizing worksheet")
    p.add_argument("--params", type=float, required=True,
                   help="model size in billions of parameters, e.g. 7, 13, 70")
    p.add_argument("--quant", default="q4_k_m",
                   choices=sorted(BYTES_PER_WEIGHT), help="weight precision")
    p.add_argument("--context", type=int, default=8192,
                   help="context length in tokens (for KV-cache estimate)")
    p.add_argument("--batch", type=int, default=1, help="concurrent sequences")
    p.add_argument("--overhead", type=float, default=0.18,
                   help="framework/activation overhead fraction (~0.15-0.20)")
    a = p.parse_args()

    bpw = BYTES_PER_WEIGHT[a.quant]
    weights = a.params * 1e9 * bpw
    kv = (KV_BYTES_PER_TOKEN_PER_B * a.params) * a.context * a.batch
    overhead = (weights + kv) * a.overhead
    total = weights + kv + overhead

    print(f"Model:        {a.params:g}B  @ {a.quant}  ({bpw} bytes/weight)")
    print(f"Context:      {a.context} tokens x batch {a.batch}")
    print("-" * 48)
    print(f"  weights      {gib(weights):8.2f} GiB")
    print(f"  KV cache     {gib(kv):8.2f} GiB   (grows with context!)")
    print(f"  overhead     {gib(overhead):8.2f} GiB   ({a.overhead:.0%})")
    print("-" * 48)
    print(f"  TOTAL        {gib(total):8.2f} GiB")
    for cap in (16, 24, 48, 80):
        fits = "FITS" if gib(total) <= cap else "does NOT fit"
        print(f"    -> {cap:>3} GB card/box: {fits}")
    print("\nReminder: rules of thumb only. Re-verify on your real runner.")


if __name__ == "__main__":
    main()
