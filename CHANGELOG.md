# Changelog

## [1.0.7] - 2026-03-21

### Added

- `Railtie`: initializer `vert.consumer_paths` que adiciona automaticamente `app/consumers` ao `autoload_paths` e `eager_load_paths` quando o diretório existe. Elimina a necessidade de configuração manual em cada serviço e garante que `rake sneakers:run` descubra todos os workers via `Rails.application.eager_load!`.

## [1.0.6] - 2026-03-21

### Fixed

- `BaseConsumer`: adiciona hook `inherited` para registrar subclasses concretas no `Sneakers::Worker::Classes`. O `include Sneakers::Worker` na classe base não propaga o registro via herança (é ativado apenas via `included` hook de módulo). Sem isso, `rake sneakers:run` não encontra workers.

## [1.0.5] - 2026-03-21

### Fixed

- `BaseConsumer`: remove a própria classe do registro `Sneakers::Worker::Classes` para evitar que o Sneakers tente iniciar um worker com `queue_name = nil` (apenas subclasses concretas com `from_queue` devem ser registradas).

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
