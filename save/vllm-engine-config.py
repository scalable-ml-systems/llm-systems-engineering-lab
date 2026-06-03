from vllm import LLM, EngineArgs

# Create EngineArgs exactly as vllm serve would
engine_args = EngineArgs(
    model="meta-llama/Llama-3.1-8B-Instruct",
    gpu_memory_utilization=0.9,
    max_model_len=None,   # Let vLLM infer
)

# Convert to EngineConfig (this is the real runtime config)
engine_config = engine_args.create_engine_config()

print("\n=== EngineConfig ===")
print(engine_config)

print("\n=== ModelConfig ===")
print(engine_config.model_config)

print("\n=== CacheConfig ===")
print(engine_config.cache_config)

print("\n=== SchedulerConfig ===")
print(engine_config.scheduler_config)

print("\n=== ParallelConfig ===")
print(engine_config.parallel_config)

