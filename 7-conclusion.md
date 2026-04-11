# Conclusion {#chap:conclusion}

\todo{Summary of contributions: investigated three CRDT approaches for Denicek, built a custom OT-based event DAG inspired by Eg-walker, validated on six formative examples with a web application (mywebnicek). The key insight: the Denicek editing model is inherently OT-shaped because it relies on path-based selectors that must be transformed through concurrent structural changes.}

## Future Work

\todo{Optimized implementation: current replay-from-scratch is correct but slow. Build incremental version with cached partial materializations. Model-guided fuzzing: use this implementation as reference oracle to test the optimized one. myDatnicek: data-oriented variant for larger datasets. Event compaction: garbage-collect old events once all peers have seen them.}
