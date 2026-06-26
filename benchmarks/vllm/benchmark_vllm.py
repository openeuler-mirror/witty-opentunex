import time
import argparse
import concurrent.futures
import numpy as np
from openai import OpenAI

def run_single_stream(client, model, prompt, max_tokens):
    t0 = time.time()
    first_token_time = None
    token_count = 0
    resp = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        max_tokens=max_tokens,
        stream=True,
    )
    for chunk in resp:
        if chunk.choices and chunk.choices[0].delta.content:
            if token_count == 0:
                first_token_time = time.time()
            token_count += 1
    t1 = time.time()
    ttft = (first_token_time - t0) if first_token_time else 0
    decode_time = (t1 - first_token_time) if first_token_time else (t1 - t0)
    tpot = decode_time / max(token_count - 1, 1)
    return token_count, ttft, tpot

def run_benchmark(client, model, prompt, max_tokens, concurrency):
    results = []
    wall_start = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(run_single_stream, client, model, prompt, max_tokens) for _ in range(concurrency)]
        for f in concurrent.futures.as_completed(futures):
            results.append(f.result())
    wall_end = time.time()
    wall_time = wall_end - wall_start
    total_tokens = sum(r[0] for r in results)
    throughput = total_tokens / wall_time
    tpot_list = [r[2] for r in results]
    ttft_list = [r[1] for r in results]
    return total_tokens, wall_time, throughput, tpot_list, ttft_list

def main():
    parser = argparse.ArgumentParser(description="DeepSeek-V4-Flash Benchmark")
    parser.add_argument("--host", type=str, default="http://127.0.0.1:8080")
    parser.add_argument("--model", type=str, default="dskv4_flash")
    parser.add_argument("--max-tokens", type=int, default=512)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--rounds", type=int, default=2)
    parser.add_argument("--concurrency", type=str, default="1,8")
    parser.add_argument("--input-tokens", type=str, default="1024,32768")
    parser.add_argument("--prompt-dir", type=str, default="benchmark_prompts")
    args = parser.parse_args()

    client = OpenAI(base_url=f"{args.host}/v1", api_key="EMPTY")
    concurrency_levels = [int(x) for x in args.concurrency.split(",")]
    input_token_levels = [int(x) for x in args.input_tokens.split(",")]

    prompts = {}
    for sz in input_token_levels:
        path = f"{args.prompt_dir}/prompt_{sz}.txt"
        with open(path, "r") as f:
            prompts[sz] = f.read()

    print("=" * 72)
    print("DeepSeek-V4-Flash Benchmark")
    print("=" * 72)
    print(f"Model: {args.model}")
    print(f"Max output tokens: {args.max_tokens}")
    print(f"Warmup rounds: {args.warmup}")
    print(f"Test rounds: {args.rounds}")
    print(f"Concurrency levels: {concurrency_levels}")
    print(f"Input token sizes: {input_token_levels}")
    print(f"Prompt dir: {args.prompt_dir}")
    print("-" * 72)

    all_summary = []

    for input_tokens in input_token_levels:
        prompt = prompts[input_tokens]
        print(f"\n{'=' * 72}")
        print(f"Input Token Size: {input_tokens}")
        print(f"{'=' * 72}")

        print("\n[Warmup]")
        for i in range(args.warmup):
            tok, _, _ = run_single_stream(client, args.model, prompt, args.max_tokens)
            print(f"  Warmup {i+1}/{args.warmup} done, output tokens: {tok}")

        for conc in concurrency_levels:
            print(f"\n--- Concurrency={conc}, InputTokens={input_tokens} ---")
            round_throughputs = []
            round_tpot = []
            round_ttft = []

            for r in range(args.rounds):
                total_tok, wall_t, tp, tpot_l, ttft_l = run_benchmark(
                    client, args.model, prompt, args.max_tokens, conc
                )
                round_throughputs.append(tp)
                round_tpot.extend(tpot_l)
                round_ttft.extend(ttft_l)
                print(
                    f"  Round {r+1}: total_out_tokens={total_tok}, "
                    f"wall_time={wall_t:.2f}s, throughput={tp:.2f} tok/s, "
                    f"avg_tpot={np.mean(tpot_l)*1000:.2f}ms, "
                    f"avg_ttft={np.mean(ttft_l)*1000:.1f}ms"
                )

            avg_tp = np.mean(round_throughputs)
            tpot_ms = [t * 1000 for t in round_tpot]
            ttft_ms = [t * 1000 for t in round_ttft]

            entry = {
                "input_tokens": input_tokens,
                "concurrency": conc,
                "throughput_mean": avg_tp,
                "tpot_mean_ms": np.mean(tpot_ms),
                "tpot_median_ms": np.median(tpot_ms),
                "tpot_p90_ms": np.percentile(tpot_ms, 90),
                "tpot_p99_ms": np.percentile(tpot_ms, 99),
                "ttft_mean_ms": np.mean(ttft_ms),
                "ttft_median_ms": np.median(ttft_ms),
                "ttft_p99_ms": np.percentile(ttft_ms, 99),
            }
            all_summary.append(entry)

            print(f"  >> Throughput: {avg_tp:.2f} tok/s | "
                  f"TPOT mean={entry['tpot_mean_ms']:.2f}ms p99={entry['tpot_p99_ms']:.2f}ms | "
                  f"TTFT mean={entry['ttft_mean_ms']:.1f}ms p99={entry['ttft_p99_ms']:.1f}ms")

    print("\n" + "=" * 72)
    print("FINAL SUMMARY")
    print("=" * 72)
    header = (
        f"{'InputTok':>9} {'Conc':>5} "
        f"{'Throughput':>12} "
        f"{'TPOT_mean':>10} {'TPOT_p99':>10} "
        f"{'TTFT_mean':>10} {'TTFT_p99':>10}"
    )
    print(header)
    print(f"{'':>9} {'':>5} {'(tok/s)':>12} {'(ms)':>10} {'(ms)':>10} {'(ms)':>10} {'(ms)':>10}")
    print("-" * 72)
    for e in all_summary:
        row = (
            f"{e['input_tokens']:>9} {e['concurrency']:>5} "
            f"{e['throughput_mean']:>12.2f} "
            f"{e['tpot_mean_ms']:>10.2f} {e['tpot_p99_ms']:>10.2f} "
            f"{e['ttft_mean_ms']:>10.1f} {e['ttft_p99_ms']:>10.1f}"
        )
        print(row)
    print("=" * 72)

if __name__ == "__main__":
    main()

