# Vert

Gem genérica de padrões para aplicações Rails: contexto de request, RLS, Outbox, Health, autorização RBAC/ABAC e concerns opcionais (multi-tenant, auditável, soft delete, UUID, document store). Tudo é **opcional** e configurável via initializer.

## Instalação

Adicione ao `Gemfile` (nome da gem no RubyGems é `vert-core`; o módulo continua `Vert`):

```ruby
gem "vert-core"
```

Execute:

```bash
bundle install
rails generate vert:install
```

Edite `config/initializers/vert.rb` e ative apenas os recursos que precisar.

## Configuração

Em `config/initializers/vert.rb`:

```ruby
Vert.configure do |config|
  config.enable_rls = true
  config.enable_outbox = true
  config.enable_health = true
  config.auto_mount_health_routes = false
  config.rabbitmq_url = ENV.fetch("RABBITMQ_URL", "amqp://guest:guest@localhost:5672/")
  config.exchange_name = "vert.events"
  config.document_service_url = ENV["DOCUMENT_SERVICE_URL"]
  config.enable_authorization = true
end
```

| Opção | Descrição | Padrão |
|-------|-----------|--------|
| `enable_rls` | Row Level Security (PostgreSQL) | `false` |
| `enable_outbox` | Publicação de eventos via Outbox | `false` |
| `enable_health` | Endpoints e checks de health | `true` |
| `auto_mount_health_routes` | Montar rotas de health automaticamente | `false` |
| `enable_authorization` | RBAC/ABAC com Pundit | `false` |
| `health_check_database` | Incluir check de DB no health | `true` |
| `health_check_redis` | Incluir check de Redis | `false` |
| `health_check_rabbitmq` | Incluir check de RabbitMQ | `false` |
| `health_check_sidekiq` | Incluir check de Sidekiq | `false` |

## Uso

### Contexto de request (Current)

Sempre disponível. Defina o contexto após autenticação:

```ruby
Vert::Current.set_context(tenant_id: "...", user_id: "...", company_id: "...")
```

Leitura: `Vert::Current.tenant_id`, `Vert::Current.user_id`, `Vert::Current.company_set?`, `Vert::Current.require_tenant!`.

Para herdar no app: `class Current < Vert::Current; end` (gerado pelo `vert:install`).

### RLS (Row Level Security)

1. `config.enable_rls = true`
2. Gere migrações: `rails generate vert:rls_migration --tables orders items`
3. No `ApplicationController`: `include Vert::Rls::ControllerContext`
4. Configure `Vert::Current` antes de cada request (ex.: no auth).

### Outbox

1. `config.enable_outbox = true`
2. Model `OutboxEvent` e migration criados pelo `vert:install`
3. Dentro de uma transação: `OutboxEvent.publish_for(record, event_type: "order.created", payload: { ... })`
4. Agende `Vert::Outbox::PublisherJob` (ex.: Sidekiq-Cron a cada 10s).

### Health

- `GET /health` → `Vert::Health.check_all`
- `GET /health/live` → liveness
- `GET /health/ready` → readiness (DB)

Rotas podem ser montadas pelo generator ou com `Vert.config.auto_mount_health_routes = true`. Checks customizados:

```ruby
Vert::Health.add_check(:external_api) do
  # return { status: "ok" } or { status: "error", message: "..." }
end
```

### Autorização (Pundit)

1. `config.enable_authorization = true`
2. No `ApplicationController`: `include Pundit::Authorization` e `include Vert::Authorization::ControllerMethods`
3. Políticas: herde de `Vert::Authorization::DynamicPolicy` e use `has_permission?("resource.action")`
4. No controller: `authorize_with_context(record)` ou `authorize_with_context(record, :approve?)`

### Concerns em models

Inclua conforme necessário (não dependem de flags, exceto document_storeable que usa `config.document_service_url`):

- `Vert::Concerns::UuidPrimaryKey`
- `Vert::Concerns::MultiTenant`
- `Vert::Concerns::Auditable`
- `Vert::Concerns::SoftDeletable`
- `Vert::Concerns::CompanyScoped`
- `Vert::Concerns::DocumentStoreable` (requer document service)

### Jobs e contexto

Para propagar tenant/user em jobs Sidekiq:

```ruby
class MyJob < ApplicationJob
  include Vert::Rls::JobContext
  def perform(id)
    # Vert::Current.tenant_id disponível
  end
end
```

## Produção e segurança

- Defina sempre via **variáveis de ambiente** em produção: `RABBITMQ_URL`, `DOCUMENT_SERVICE_URL`, `REDIS_URL`. Os valores padrão (guest/localhost) são apenas para desenvolvimento.
- Serviços que publicam mensagens nas filas consumidas com `Vert::Rls::ConsumerContext` podem definir o contexto (tenant_id, user_id) via headers; garanta que apenas serviços confiáveis publiquem nessas filas.
- Para mais detalhes, veja `SECURITY_AND_QUALITY_AUDIT.md` no repositório.

## Licença

MIT.
