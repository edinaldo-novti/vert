# frozen_string_literal: true

module Vert
  module Health
    class Checker
      attr_reader :checks

      def initialize
        @checks = {}
        setup_default_checks
      end

      def add_check(name, &block)
        @checks[name] = block
      end

      alias register add_check

      def remove_check(name)
        @checks.delete(name)
      end

      def check_all
        results = {}
        overall_healthy = true

        @checks.each do |name, check|
          result = check.call
          results[name] = result
          overall_healthy = false unless result[:status] == "ok"
        rescue StandardError => e
          results[name] = { status: "error", message: e.message }
          overall_healthy = false
        end

        {
          status: overall_healthy ? "healthy" : "unhealthy",
          timestamp: Time.current.iso8601,
          checks: results
        }
      end

      def liveness
        { status: "ok", timestamp: Time.current.iso8601 }
      end

      def readiness
        db_ok = check_database[:status] == "ok"
        {
          status: db_ok ? "ready" : "not_ready",
          timestamp: Time.current.iso8601,
          checks: { database: check_database }
        }
      end

      def check_database
        ActiveRecord::Base.connection.execute("SELECT 1")
        { status: "ok" }
      rescue StandardError => e
        { status: "error", message: e.message }
      end

      def check_redis
        return { status: "skipped", message: "Redis check disabled" } unless Vert.config.health_check_redis
        return { status: "skipped", message: "Redis not configured" } unless redis_available?

        Redis.current.ping == "PONG" ? { status: "ok" } : { status: "error", message: "Ping failed" }
      rescue StandardError => e
        { status: "error", message: e.message }
      end

      def check_rabbitmq
        return { status: "skipped", message: "RabbitMQ check disabled" } unless Vert.config.health_check_rabbitmq

        connection = Bunny.new(Vert.config.rabbitmq_url, connection_timeout: 5)
        connection.start
        connection.close
        { status: "ok" }
      rescue StandardError => e
        { status: "error", message: e.message }
      end

      def check_sidekiq
        return { status: "skipped", message: "Sidekiq check disabled" } unless Vert.config.health_check_sidekiq
        return { status: "skipped", message: "Sidekiq not configured" } unless sidekiq_available?

        stats = Sidekiq::Stats.new
        { status: "ok", processed: stats.processed, failed: stats.failed, queues: stats.queues }
      rescue StandardError => e
        { status: "error", message: e.message }
      end

      class << self
        def checker
          @checker ||= new
        end

        delegate :check_all, :liveness, :readiness, :add_check, :register, to: :checker
      end

      private

      def setup_default_checks
        add_check(:database) { check_database } if Vert.config.health_check_database
        add_check(:redis) { check_redis } if Vert.config.health_check_redis
        add_check(:rabbitmq) { check_rabbitmq } if Vert.config.health_check_rabbitmq
        add_check(:sidekiq) { check_sidekiq } if Vert.config.health_check_sidekiq
      end

      def redis_available?
        defined?(Redis) && Redis.respond_to?(:current)
      end

      def sidekiq_available?
        defined?(Sidekiq::Stats)
      end
    end
  end
end
