# Changelog

## [1.0.0] - 2025-03-14

### Added

- Initial release.
- Configuration via `Vert.configure` (optional RLS, Outbox, Health, Authorization, concerns).
- Concerns: Current, UuidPrimaryKey, MultiTenant, Auditable, SoftDeletable, CompanyScoped, DocumentStoreable.
- Outbox: Event, Publisher, PublisherJob.
- RLS: ConnectionHandler, ContextMiddleware, JobContext, BaseConsumer.
- Health: Checker, Routes, ControllerMixin.
- Authorization: PermissionResolver, DynamicPolicy, PolicyFinder, ControllerMethods.
- Generators: `vert:install`, `vert:rls_migration`.
