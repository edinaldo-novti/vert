# Auditoria de Qualidade e Segurança — Gem vert-core

**Data:** 2025-03  
**Escopo:** `services/00-gems/vert` (publicada no RubyGems como `vert-core`)  
**Objetivo:** Garantir segurança e confiabilidade para uso em produção.

---

## 1. Resumo executivo

| Categoria        | Status | Observação |
|------------------|--------|------------|
| Segurança        | ✅ Aprovado com ressalvas | Sem vulnerabilidades críticas; ver itens 2.x |
| Qualidade        | ✅ Bom | Código consistente; ver itens 3.x |
| Dependências     | ✅ OK | Rails 7–9, Sidekiq, Bunny, Discard — versões declaradas |
| Publicação       | ⚠️ Ajuste | CI usa Ruby 2.6; gemspec exige >= 3.2 |

---

## 2. Segurança

### 2.1 Pontos positivos

- **SQL:** Uso de `ActiveRecord::Base.sanitize_sql` em `ConnectionHandler` para `SET LOCAL` (tenant_id, company_id, user_id). Nenhuma concatenação direta de input em SQL.
- **Autorização:** Queries em `PermissionResolver` usam placeholders (`?`). Nenhum `eval`, `YAML.load` ou `Marshal.load` em dados de usuário ou mensagens.
- **Contexto de job:** `Vert::Current.serialize/deserialize` só manipula Hash com atributos primitivos (tenant_id, user_id, company_id, request_id). Não há deserialização insegura.
- **Constantes:** `Object.const_get` em `PolicyFinder` e `OutboxEvent` usa apenas nomes derivados do modelo/record da aplicação, não de input do usuário.
- **Secrets:** Nenhuma senha, token ou API key hardcoded. URLs e credenciais vêm de `Vert.config` ou `ENV`.

### 2.2 Riscos e recomendações

| Risco | Severidade | Recomendação |
|-------|------------|--------------|
| **Defaults de conexão** | Baixo | `Configuration` usa `ENV.fetch(..., "amqp://guest:guest@localhost:5672/")` e `redis://localhost:6379/0`. Em produção, garantir sempre variáveis de ambiente; considerar remover defaults “guest” em doc ou comentar que são apenas para desenvolvimento. |
| **Document service** | Baixo | `DocumentServiceClient` não valida `base_url`. Garantir que `document_service_url` não seja controlada por usuário (evitar SSRF). Em produção usar HTTPS. |
| **Health / rotas** | Baixo | `Vert::Health::Routes.mount(router, path: nil)` usa `path` em `scope path`. O valor vem de `Vert.config.health_check_path` (default `/health`). Se a app permitir config dinâmico a partir de input, poderia haver path traversal; uso normal é seguro. |
| **Resposta 403** | Info | `render_forbidden` expõe `permission` (nome do método da policy) e `resource` (nome da classe). Pode ser desejável em APIs internas; em APIs públicas considerar resposta genérica para não revelar estrutura. |
| **Cache de permissões (Redis)** | Baixo | `invalidate_user_cache(user_id)` monta a chave `vert:permissions:#{user_id}:*`. Se `user_id` puder conter `*` ou `?`, o padrão Redis poderia invalidar mais chaves. Recomendação: usar apenas IDs válidos (UUID/integer) ou escapar/sanitizar. |
| **Consumers RabbitMQ** | Médio (contexto) | `ConsumerContext` define contexto (tenant_id, user_id, company_id) a partir dos headers da mensagem. Qualquer produtor da fila pode “personificar” um tenant. Garantir que apenas serviços confiáveis publiquem nessas filas e que a rede do broker seja controlada. |

### 2.3 O que não foi encontrado

- Uso de `eval`, `exec`, `system`, backticks ou `Kernel#open` com input externo.
- `YAML.load` ou `Marshal.load` em dados de request ou mensagens.
- Exposição de stack trace ou detalhes internos em respostas de erro (apenas mensagens controladas).
- Credenciais ou tokens fixos no código.

---

## 3. Qualidade

### 3.1 Estrutura e convenções

- `# frozen_string_literal: true` e estilo consistente.
- Separação clara: concerns, clients, RLS, outbox, health, authorization.
- Entry point único: `vert_core.rb` → `vert.rb`; Railtie condicional.

### 3.2 Tratamento de erros

- `ConnectionHandler`: `rescue StandardError` com log e re-raise em `set_context`; em `reset_context` apenas log (evita mascarar falhas de reset).
- `DocumentServiceClient`: `execute_request` retorna hash `{ success:, error:, ... }`; não propaga exceção para o caller, adequado para cliente HTTP.
- `Publisher#publish`: `rescue StandardError` → `mark_as_failed!` e retorno `false`.
- Health checks: cada check em `check_all` em bloco próprio com `rescue` para não derrubar os demais.

### 3.3 Configuração

- Flags explícitas (enable_rls, enable_outbox, etc.) com default seguro (maioria `false`; health `true`).
- Documentação no README e no template do initializer.

### 3.4 Melhorias sugeridas

- **Configuração sensível:** Considerar um método `Vert.config.to_s` ou inspetor que oculte `rabbitmq_url` e `document_service_url` em logs (ex.: mostrar só host/scheme).
- **Versão do Ruby no CI:** Alinhar o workflow ao `required_ruby_version` (>= 3.2) para evitar publicar com Ruby incompatível.

---

## 4. Gemspec e publicação

- **Nome:** `vert-core` (require: `vert_core`); módulo: `Vert`. Consistente.
- **Licença:** MIT. Adequado.
- **Dependências:** activesupport/activerecord 7–9, bunny ~> 2.22, discard ~> 1.3, sidekiq 7–9. Ranges claros.
- **CI:** `.github/workflows/gem-push.yml` usa Ruby 2.6; o gemspec exige `>= 3.2.0`. **Correção necessária:** usar Ruby 3.2 (ou 3.3) no workflow.

---

## 5. Checklist pós-auditoria

- [ ] Atualizar workflow para Ruby 3.2+.
- [ ] Documentar na README que defaults de RabbitMQ/Redis são apenas para desenvolvimento.
- [ ] (Opcional) Sanitizar/validar `user_id` em chaves de cache no `PermissionResolver`.
- [ ] (Opcional) Resposta 403 mais genérica em ambientes públicos.
- [ ] Manter dependências atualizadas (`bundle audit` / Dependabot).

---

## 6. Conclusão

A gem **vert-core** está em bom estado para uso em produção do ponto de vista de segurança e qualidade. Não foram identificadas vulnerabilidades críticas ou altas. As recomendações são sobretudo de configuração (ENV em produção, confiança em produtores de mensagens), alinhamento do CI ao Ruby 3.2+ e pequenos ajustes opcionais de hardening e documentação.
