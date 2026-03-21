# Changelog

## [1.0.4] - 2026-03-21

### Fixed

- `BaseConsumer`: corrigido bug de ordem de carregamento em que `if defined?(Sneakers::Worker)` era avaliado antes do Sneakers ser carregado no contexto Rake (`sneakers:run`), resultando em `NoMethodError: undefined method 'from_queue'`. Alterado para `require "sneakers"` com `rescue LoadError` para garantir o include correto independente da ordem de boot.

## [1.0.3] - 2026-03-21

### Fixed

- `Configuration`: default `rabbitmq_url` corrigido de `amqp://guest:guest@localhost` para `amqp://vfarma:vfarma123@localhost:5672/`.
- `Configuration`: default `exchange_name` corrigido de `"vert.events"` para `"verticalerp.events"` (alinhado ao exchange canônico do projeto).

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
