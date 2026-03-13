# frozen_string_literal: true

module Vert
  module Authorization
    class PermissionResolver
      CACHE_TTL = 5.minutes
      CACHE_PREFIX = "vert:permissions"

      class << self
        def has_permission?(user, permission_code, context = {})
          return false unless user
          return true if super_admin?(user)

          cached = get_cached_permission(user, permission_code, context)
          return cached unless cached.nil?

          result = resolve_permission(user, permission_code, context)
          cache_permission(user, permission_code, context, result)
          result
        end

        def get_condition(user, permission_code, condition_key, context = {})
          return nil unless user
          conditions = get_permission_conditions(user, permission_code, context)
          conditions&.dig(condition_key.to_s)
        end

        def get_allowed_fields(user, permission_code, context = {})
          return nil if super_admin?(user)
          fields = get_field_restrictions(user, permission_code, context)
          fields&.dig("granted_fields")
        end

        def get_denied_fields(user, permission_code, context = {})
          return [] if super_admin?(user)
          fields = get_field_restrictions(user, permission_code, context)
          fields&.dig("denied_fields") || []
        end

        def user_permissions(user, context = {})
          return [] unless user
          return ["*"] if super_admin?(user)

          cache_key = user_permissions_cache_key(user, context)
          cached = redis_get(cache_key)
          return cached if cached

          permissions = collect_user_permissions(user, context)
          redis_set(cache_key, permissions, CACHE_TTL)
          permissions
        end

        def invalidate_user_cache(user_id)
          pattern = "#{CACHE_PREFIX}:#{user_id}:*"
          redis_delete_pattern(pattern)
        end

        def invalidate_role_cache(role_id)
          if defined?(UserRole)
            UserRole.where(role_id: role_id).pluck(:user_id).each { |user_id| invalidate_user_cache(user_id) }
          end
        end

        private

        def resolve_permission(user, permission_code, context)
          company_id = context[:company_id]
          return false if has_direct_deny?(user, permission_code, company_id)
          return true if has_direct_grant?(user, permission_code, company_id)

          effective_roles(user, company_id).each do |role|
            return true if role_has_permission?(role, permission_code)
          end
          false
        end

        def has_direct_deny?(user, permission_code, company_id)
          return false unless defined?(UserPermission)
          UserPermission
            .joins(:permission)
            .where(user_id: user.id, grant_type: "deny")
            .where("permissions.code = ?", permission_code)
            .where("company_id IS NULL OR company_id = ?", company_id)
            .where("valid_from <= ? AND (valid_until IS NULL OR valid_until >= ?)", Time.current, Time.current)
            .exists?
        end

        def has_direct_grant?(user, permission_code, company_id)
          return false unless defined?(UserPermission)
          UserPermission
            .joins(:permission)
            .where(user_id: user.id, grant_type: "grant")
            .where("permissions.code = ?", permission_code)
            .where("company_id IS NULL OR company_id = ?", company_id)
            .where("valid_from <= ? AND (valid_until IS NULL OR valid_until >= ?)", Time.current, Time.current)
            .exists?
        end

        def effective_roles(user, company_id)
          return [] unless defined?(UserRole)
          role_ids = UserRole
            .where(user_id: user.id)
            .where("company_id IS NULL OR company_id = ?", company_id)
            .where("valid_from <= ? AND (valid_until IS NULL OR valid_until >= ?)", Time.current, Time.current)
            .pluck(:role_id)
          return [] if role_ids.empty?
          Role.where(id: role_ids).or(Role.where(id: inherited_role_ids(role_ids))).where(is_active: true).order(priority: :desc)
        end

        def inherited_role_ids(role_ids, collected = [])
          return collected if role_ids.empty?
          parent_ids = Role.where(id: role_ids).where.not(parent_role_id: nil).pluck(:parent_role_id)
          new_parents = parent_ids - collected
          return collected if new_parents.empty?
          inherited_role_ids(new_parents, collected + new_parents)
        end

        def role_has_permission?(role, permission_code)
          return false unless defined?(RolePermission)
          RolePermission.joins(:permission).where(role_id: role.id).where("permissions.code = ?", permission_code).exists?
        end

        def get_permission_conditions(user, permission_code, context)
          company_id = context[:company_id]
          conditions = {}
          if defined?(UserPermission)
            user_conditions = UserPermission
              .joins(:permission)
              .where(user_id: user.id, grant_type: "grant")
              .where("permissions.code = ?", permission_code)
              .where("company_id IS NULL OR company_id = ?", company_id)
              .pluck(:conditions).compact
            user_conditions.each { |c| conditions.merge!(c) if c.is_a?(Hash) }
          end
          effective_roles(user, company_id).each do |role|
            if defined?(RolePermission)
              role_conditions = RolePermission
                .joins(:permission)
                .where(role_id: role.id)
                .where("permissions.code = ?", permission_code)
                .pluck(:conditions).compact
              role_conditions.each { |c| conditions.merge!(c) if c.is_a?(Hash) }
            end
          end
          if defined?(Permission)
            perm = Permission.find_by(code: permission_code)
            conditions.merge!(perm.conditions) if perm&.conditions.is_a?(Hash)
          end
          conditions
        end

        def get_field_restrictions(user, permission_code, context)
          company_id = context[:company_id]
          if defined?(UserPermission)
            user_perm = UserPermission
              .joins(:permission)
              .where(user_id: user.id)
              .where("permissions.code = ?", permission_code)
              .where("company_id IS NULL OR company_id = ?", company_id)
              .first
            return user_perm.attributes.slice("granted_fields", "denied_fields") if user_perm
          end
          effective_roles(user, company_id).each do |role|
            if defined?(RolePermission)
              role_perm = RolePermission
                .joins(:permission)
                .where(role_id: role.id)
                .where("permissions.code = ?", permission_code)
                .first
              return role_perm.attributes.slice("granted_fields", "denied_fields") if role_perm
            end
          end
          nil
        end

        def collect_user_permissions(user, context)
          permissions = Set.new
          company_id = context[:company_id]
          if defined?(UserPermission)
            UserPermission
              .joins(:permission)
              .where(user_id: user.id, grant_type: "grant")
              .where("company_id IS NULL OR company_id = ?", company_id)
              .where("valid_from <= ? AND (valid_until IS NULL OR valid_until >= ?)", Time.current, Time.current)
              .pluck("permissions.code")
              .each { |code| permissions.add(code) }
          end
          effective_roles(user, company_id).each do |role|
            if defined?(RolePermission)
              RolePermission.joins(:permission).where(role_id: role.id).pluck("permissions.code").each { |code| permissions.add(code) }
            end
          end
          if defined?(UserPermission)
            UserPermission
              .joins(:permission)
              .where(user_id: user.id, grant_type: "deny")
              .where("company_id IS NULL OR company_id = ?", company_id)
              .pluck("permissions.code")
              .each { |code| permissions.delete(code) }
          end
          permissions.to_a
        end

        def super_admin?(user)
          user.respond_to?(:super_admin?) && user.super_admin?
        end

        def cache_key(user, permission_code, context)
          company_id = context[:company_id] || "all"
          "#{CACHE_PREFIX}:#{user.id}:#{company_id}:#{permission_code}"
        end

        def user_permissions_cache_key(user, context)
          company_id = context[:company_id] || "all"
          "#{CACHE_PREFIX}:#{user.id}:#{company_id}:all"
        end

        def get_cached_permission(user, permission_code, context)
          result = redis_get(cache_key(user, permission_code, context))
          result.nil? ? nil : (result == "true")
        end

        def cache_permission(user, permission_code, context, result)
          redis_set(cache_key(user, permission_code, context), result.to_s, CACHE_TTL)
        end

        def redis_get(key)
          return nil unless redis_available?
          value = redis.get(key)
          value.nil? ? nil : (JSON.parse(value) rescue value)
        end

        def redis_set(key, value, ttl)
          redis.setex(key, ttl.to_i, value.to_json) if redis_available?
        end

        def redis_delete_pattern(pattern)
          return unless redis_available?
          keys = redis.keys(pattern)
          redis.del(*keys) if keys.any?
        end

        def redis_available?
          defined?(Redis) && redis.present?
        end

        def redis
          @redis ||= (Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0")) if defined?(Redis))
        end
      end
    end
  end
end
