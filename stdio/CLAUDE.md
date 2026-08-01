# hex_local

## Knowledge Base

- When debugging errors or investigating issues in this project, call `recall` with the error message or topic to check for known pain points before investigating from scratch.
- After solving a non-trivial bug or learning something worth preserving, call `remember` to save the learning.
- When asked to search documentation for specific libraries or packages (e.g. `boruta`, `anubis_mcp`, `phoenix`, `plug`), **ALWAYS extract the target package name(s)** and pass it explicitly in the `package` argument of `search_docs` (e.g. `package: "boruta"`) to trigger Hex.pm auto-ingestion into SQLite if not yet indexed.
- **Citing Package Versions**: When referencing documentation returned by `search_docs`, **ALWAYS include the package version(s)** returned in the search result payload (e.g. `anubis_mcp v1.14.0`, `boruta v3.0.0-beta.4`).
