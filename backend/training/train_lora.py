"""
QLoRA fine-tune of a small open model on the synthesized Ops training data,
then export straight to GGUF so it can be imported into Ollama and dropped
into the existing LLM_PROVIDER=ollama swap point in agent/crew.py with zero
orchestration changes.

Targets a local 6GB-class GPU (tested against an RTX 4050 Laptop, 6GB VRAM) —
Qwen2.5-3B-Instruct in 4-bit fits comfortably via Unsloth. If you don't have a
local NVIDIA GPU, run this same script on a free Google Colab T4 instance
instead (Runtime > Change runtime type > T4 GPU), then download the GGUF.

This needs a SEPARATE Python environment from backend/venv — these are heavy
CUDA-specific packages (~5-8GB) that have no business in the FastAPI backend
env. See backend/training/requirements.txt.

Windows note: Unsloth's Windows support can be finicky with bitsandbytes. If
`pip install -r requirements.txt` or the run below fails with a bitsandbytes/
CUDA error, the reliable fallback is WSL2 (Ubuntu) with the same requirements
file — Unsloth's Linux path is the well-trodden one.

Usage (from backend/training/, inside the training venv):
    python train_lora.py --data-dir data --out models/handled-ops-qwen2.5-3b
"""

import argparse
import glob
import json
from pathlib import Path


def load_dataset_jsonl(data_dir):
    from datasets import Dataset

    rows = []
    for path in glob.glob(str(Path(data_dir) / "*.jsonl")):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    rows.append(json.loads(line))
    if not rows:
        raise SystemExit(
            f"No .jsonl files found in {data_dir} — run synthesize_data.py --all first."
        )
    print(f"Loaded {len(rows)} examples from {data_dir}")
    return Dataset.from_list(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", default="data")
    ap.add_argument("--base-model", default="unsloth/Qwen2.5-3B-Instruct-bnb-4bit")
    ap.add_argument("--out", default="models/handled-ops-qwen2.5-3b")
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--max-seq-length", type=int, default=2048)
    ap.add_argument("--quant", default="q4_k_m", help="GGUF quantization for export")
    args = ap.parse_args()

    import torch
    from unsloth import FastLanguageModel
    from trl import SFTTrainer, SFTConfig

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=args.base_model,
        max_seq_length=args.max_seq_length,
        load_in_4bit=True,
    )
    model = FastLanguageModel.get_peft_model(
        model,
        r=16,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                         "gate_proj", "up_proj", "down_proj"],
        lora_alpha=16,
        lora_dropout=0,
        bias="none",
        use_gradient_checkpointing="unsloth",
    )

    dataset = load_dataset_jsonl(args.data_dir)

    def format_example(ex):
        return {"text": tokenizer.apply_chat_template(
            ex["messages"], tokenize=False, add_generation_prompt=False
        )}

    dataset = dataset.map(format_example)

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        dataset_text_field="text",
        max_seq_length=args.max_seq_length,
        args=SFTConfig(
            per_device_train_batch_size=2,
            gradient_accumulation_steps=4,
            num_train_epochs=args.epochs,
            learning_rate=2e-4,
            fp16=not torch.cuda.is_bf16_supported(),
            bf16=torch.cuda.is_bf16_supported(),
            logging_steps=10,
            output_dir=str(Path(args.out).parent / "checkpoints"),
            optim="adamw_8bit",
            seed=42,
        ),
    )
    trainer.train()

    Path(args.out).mkdir(parents=True, exist_ok=True)
    print(f"Exporting GGUF ({args.quant}) to {args.out} ...")
    model.save_pretrained_gguf(args.out, tokenizer, quantization_method=args.quant)

    gguf_files = list(Path(args.out).glob("*.gguf"))
    gguf_name = gguf_files[0].name if gguf_files else "<model>.gguf"
    print(f"""
Done. GGUF at: {args.out}/{gguf_name}

To import into Ollama:
    cd {args.out}
    echo FROM ./{gguf_name} > Modelfile
    ollama create handled-ops -f Modelfile

Then in backend/.env:
    LLM_PROVIDER=ollama
    LLM_MODEL=handled-ops
""")


if __name__ == "__main__":
    main()
