# Changelog

## [1.0.14] - 2026-05-24

### Added

- `Vert::Auth::JwtAuthenticatable#jwt_authenticated?` — helper que retorna `true` após `authenticate_jwt!` ter populado o payload com sucesso. Necessário durante o rollout para usar em `before_action :foo, if: :jwt_authenticated?` (callbacks que dependem de `Vert::Current` já populado).

## [1.0.13] - 2026-05-24

### Added

- `Vert::Auth::JwtAuthenticatable`: nova concern de autenticação JWT Bearer que estabelece o contexto multi-tenant via `Vert::Current` lendo **exclusivamente** os claims do JWT (regra inviolável 2 do projeto — nunca confiar em parâmetros do cliente).
  - Valida o header `X-Tenant-ID` (defesa em profundidade): se presente, precisa ser igual ao `tenant_id` do JWT, caso contrário responde **403 Forbidden** e dispara o hook `on_tenant_mismatch` (override-able por serviço para gravar em `audit_logs`).
  - Header ausente → JWT manda silenciosamente.
  - Hooks override-áveis: `jwt_secret`, `jwt_algorithm`, `tenant_header_name`, `on_tenant_mismatch`, `on_jwt_invalid`, `current_jwt_user`.
  - `skip_jwt_authentication` para opt-out em endpoints públicos (ex: `/auth/sign_in`, `/health`).
  - Opt-in via `Vert.config.enable_jwt_auth = true` no initializer.
- `Configuration#enable_jwt_auth`: nova flag (default `false`).

### Migration guide

```ruby
# config/initializers/vert.rb
Vert.configure { |c| c.enable_jwt_auth = true }

# app/controllers/api/base_controller.rb
class Api::BaseController < ApplicationController
  include Vert::Auth::JwtAuthenticatable

  # opcional: gravar mismatch em audit_logs
  def on_tenant_mismatch(jwt_tenant_id:, header_tenant_id:, user_id:)
    super
    AuditLog.create!(
      event_type: "security.tenant_mismatch",
      user_id: user_id,
      payload: { jwt: jwt_tenant_id, header: header_tenant_id,
                 ip: request.remote_ip, path: request.fullpath }
    )
  end
end
```

Corrige fragmentação dos 5 patterns de auth JWT distribuídos pelos 23 serviços do monorepo (alguns aceitavam `X-Tenant-ID` como fallback ou — pior — como fonte primária, sobrescrevendo o JWT).

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
