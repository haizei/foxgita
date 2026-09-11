# Migrate AI recipes progressively with explicit lifecycle states

Gita will migrate its four AI Recipes independently in the order next session → image plan → media review → video diagnosis. Each Recipe moves through `legacy → internalPlatform → platformDefault → removed`; internal comparison uses fixtures and recorded responses rather than issuing duplicate live model calls. This costs more temporary wiring, but isolates rollback and prevents cost, privacy exposure, and side effects from dual execution. Legacy Clients are deleted only after behavior, writes, failure degradation, copy, and internal rollout pass for every Recipe.

