"""
Standalone GGUF export for an already-merged model (from train_lora.py) —
avoids re-running the training step just to retry a failed export.

Usage: python export_gguf.py --model models/handled-ops-qwen2.5-3b --quant q4_k_m
"""
import argparse

ap = argparse.ArgumentParser()
ap.add_argument("--model", default="models/handled-ops-qwen2.5-3b")
ap.add_argument("--quant", default="q4_k_m")
args = ap.parse_args()

from unsloth import FastLanguageModel

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name=args.model,
    max_seq_length=2048,
    load_in_4bit=False,
)
model.save_pretrained_gguf(args.model, tokenizer, quantization_method=args.quant)
print(f"Done. Check {args.model}/*.gguf")
