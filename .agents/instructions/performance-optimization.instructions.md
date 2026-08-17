---
applyTo: '**/*.{cs,java,py}'
description: 'Performance guidance for backend code in this repository, focused on APIs, workers, background jobs, and data access in .NET, Java, and Python.'
---

# Performance Optimization

Use these instructions for backend code generation and code review. This repository does not need generic frontend guidance here. Focus on API latency, throughput, memory use, database/query shape, startup time, and background-job execution.

## Repo-Level Policy

- Optimize for backend services, consumers, workers, schedulers, and data-processing code.
- Prefer simple designs that keep latency predictable and memory bounded.
- Do not trade correctness or observability for micro-optimizations.
- Measure first when changing existing hot paths. For new code, choose patterns that avoid known performance traps by default.
- Keep request handlers and background-job handlers thin. Move heavy logic into focused services that can be tested and profiled.
- Minimize database round trips, payload size, allocations, and unnecessary serialization.
- Treat startup time as important for local development, container restarts, scale-out, and job activation.
- For code review, prioritize plausible production issues over speculative tuning.

## Cross-Language Priorities

### API Latency And Throughput

- Avoid blocking I/O on request paths.
- Avoid synchronous calls hidden behind asynchronous APIs.
- Keep handler logic small and defer expensive work to dedicated services or background processing when appropriate.
- Avoid repeated remote calls inside loops.
- Batch or pipeline outbound calls when the business flow permits it.
- Return only the data required by the caller.

### Memory Use

- Avoid loading entire datasets when streaming, paging, or chunking is possible.
- Avoid unnecessary copies of large collections, strings, byte arrays, or JSON payloads.
- Be careful with caching large objects or unbounded dictionaries.
- Prefer iterative processing for large imports, exports, and background workloads.

### Database And Query Shape

- Design queries for the exact access pattern.
- Avoid `SELECT *` and equivalent ORM projections that load more columns than needed.
- Eliminate N+1 query patterns.
- Keep transactions short and explicit.
- Ensure filtering, sorting, and joins align with indexing strategy.
- For bulk operations, prefer batch writes and chunked reads.

### Startup Time

- Keep application startup work minimal.
- Do not perform heavy data loading, schema scanning, warmup queries, or remote calls during startup unless strictly required.
- Defer optional initialization until the service is ready.
- Keep dependency graphs and reflection-heavy registration under control.

### Background Jobs And Workers

- Design handlers to be idempotent where possible.
- Bound concurrency explicitly; do not let queue consumers or scheduled jobs overwhelm CPU, memory, or the database.
- Prefer chunked processing with checkpoints over one large in-memory operation.
- Emit enough timing and volume telemetry to identify slow handlers and queue buildup.
- Do not keep large object graphs alive across long-running loops.

## .NET Guidance

### Development And Code Generation

- Use `async` and `await` for I/O-bound code end to end. Do not block with `.Result`, `.Wait()`, or sync-over-async patterns.
- Page Azure Table Storage results using `IAsyncPageable<T>` from `Query<T>()`; avoid loading entire result sets into memory.
- For ADO.NET queries, use explicit `SqlDbType`-typed parameters and stream results with `SqlDataReader` rather than materializing large collections.
- Avoid premature materialization with `ToList()` when further LINQ filtering is possible.
- Reuse `HttpClient` via DI. Do not create per-request clients.
- Use cancellation tokens on request paths and background handlers.
- Be careful with large LINQ chains that allocate multiple intermediate collections.
- Keep startup registration lean; avoid scanning or initializing heavy components unless required.

### Code Review Checks

- Look for hidden multiple enumerations, repeated LINQ materialization, and large intermediate allocations.
- Check ADO.NET commands for missing `SqlDbType` typing, unbounded result reads, and N+1 call patterns inside loops.
- Check Azure Table Storage usage for missing partition key filters, unbounded `Query<T>()` calls without continuation tokens, and unnecessary column projections.
- Check API handlers and consumers for blocking calls or unnecessary serialization/deserialization.
- Check background services for unbounded loops, missing delays, missing cancellation, or unlimited concurrency.
- Check logging in hot paths for expensive formatting, large object logging, or duplicate logs.

## Java Guidance

### Development And Code Generation

- Prefer non-blocking or bounded-concurrency designs for I/O-heavy code; avoid tying throughput to thread growth.
- Use database projections and targeted DTO mapping instead of loading full entities when only part of the data is needed.
- Avoid eager loading patterns that inflate latency or memory without clear benefit.
- Be deliberate with collection copying, stream pipelines, and temporary object creation in hot paths.
- Keep framework startup lean by avoiding expensive initialization and unnecessary component scanning.
- For background processing, use explicit executor sizing and backpressure-aware queue handling.
- Tune batch sizes intentionally for DB writes, message consumption, and scheduled work.

### Code Review Checks

- Look for blocking database or network calls inside loops.
- Look for oversized ORM fetch graphs, missing pagination, and entity loading that could be reduced to projections.
- Check thread pool and executor usage for unbounded growth or hidden contention.
- Check object churn in hot code paths, especially repeated mapping, parsing, or string construction.
- Check startup code for avoidable warmup work and reflection-heavy registration.

## Python Guidance

### Development And Code Generation

- Keep request and worker paths explicit about whether they are I/O-bound or CPU-bound.
- Use `asyncio` only when the surrounding stack is async and benefits from it; do not mix sync and async carelessly.
- For CPU-heavy work, prefer subprocesses, worker pools, or offloading instead of blocking a shared event loop.
- Process large datasets in chunks, generators, or iterators instead of loading them all into memory.
- Avoid repeated JSON parsing, dataframe copying, or list materialization in hot paths.
- Be conservative with in-memory caching; Python object overhead is significant.
- Keep module import side effects and startup work small.

### Code Review Checks

- Look for accidental O(n^2) loops over records, rows, or messages.
- Look for repeated conversion between lists, dicts, dataframes, and serialized forms.
- Check whether async code is actually non-blocking or still doing blocking I/O.
- Check long-running jobs for memory growth, missing chunking, and lack of checkpoints.
- Check database access for row-by-row processing that should be batched.

## Review Checklist

- Is the request path free of blocking I/O and unnecessary remote round trips?
- Is throughput limited by avoidable serialization, repeated work, or poor batching?
- Is memory use bounded for large inputs, exports, or background processing?
- Is the query shape correct for the access pattern, without N+1 behavior or oversized projections?
- Is startup work minimal and appropriate for a service or worker process?
- Are background jobs chunked, idempotent where needed, and protected from unbounded concurrency?
- Are logs and telemetry useful without making the hot path slower?
- Are any optimizations evidence-based or based on well-known backend defaults rather than guesswork?

## Output Expectations

When generating code:

- Default to patterns that are efficient enough for production backend services.
- Call out meaningful tradeoffs when a faster approach reduces readability or flexibility.
- Prefer small, safe optimizations with clear payoff.

When reviewing code:

- Report only concrete or highly plausible performance issues.
- Explain the failure mode briefly, such as increased latency, poor throughput, excess memory, slow startup, or inefficient query shape.
- Suggest the smallest correction that fits the existing stack and architecture.
