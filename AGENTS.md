# Repository rules

- BusyBox source versions and SHA256 values must be updated together in `source.env`.
- Source archives must come from the official BusyBox download site.
- Release binaries are produced by GitHub Actions, not committed to Git.
- Every supported architecture must pass the static-link and Unicode checks. Full must match its audited 411-applet baseline; Docker-compatible must match the Docker Official applet baseline and may differ from its reconstructed upstream config only by the missing subset of the four approved Unicode symbols.
- Do not weaken compatibility checks to make a build pass; document and resolve the underlying configuration issue.
- Keep architecture-specific behavior in the CI matrix or explicit target cases. Do not guess unsupported architecture mappings.
- Keep `FEATURE_USE_BSS_TAIL` disabled in Full so its effective buffer limits do not depend on architecture-specific link layout or a second build pass.
- Do not publish a Docker-compatible binary when applying the four Unicode symbols to the effective Docker Official config produces no change; all matrix targets must agree on that decision.
