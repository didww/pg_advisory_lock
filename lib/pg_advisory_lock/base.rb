# frozen_string_literal: true

require 'active_support/logger'
require 'pg_sql_caller'
require 'active_support/core_ext/string/inflections'

module PgAdvisoryLock
  class Base
    # Encapsulates advisory lock logic.
    # https://www.postgresql.org/docs/9.3/functions-admin.html#FUNCTIONS-ADVISORY-LOCKS-TABLE
    # Allows to use mutex in applications that uses same database.

    class_attribute :logger, instance_writer: false, default: ActiveSupport::Logger.new(STDOUT)
    class_attribute :_sql_caller_class, instance_writer: false, default: 'PgSqlCaller::Base'
    class_attribute :_lock_names, instance_writer: false, default: {}

    class << self
      def inherited(subclass)
        subclass._lock_names = {}
        super
      end

      # @param name [Symbol, String]
      # @param value [Integer, Array<(Integer, Integer)>]
      def register_lock(name, value)
        _lock_names[name.to_sym] = value
      end

      # @param klass [Class<PgSqlCaller::Base>, String]
      def sql_caller_class(klass)
        self._sql_caller_class = klass
      end

      # @param name [Symbol, String] - lock name (will be transformed to number).
      # @param transaction [Boolean] - if true lock will be released at the end of current transaction
      #   otherwise it will be released at the end of block.
      # @param shared [Boolean] - is lock shared or not.
      # @param id [Integer] - number that will be used in pair with lock number to perform advisory lock.
      # @yield - call block when lock is acquired
      #   block must be passed if transaction argument is false.
      # @raise [ArgumentError] when lock name is invalid.
      # @return yield
      def with_lock(name, transaction: true, shared: false, id: nil, &block)
        new(name, transaction: transaction, shared: shared, id: id).lock(&block)
      end
    end

    # @param name [Symbol, String] - lock name (will be transformed to number).
    # @param transaction [Boolean] - if true lock will be released at the end of current transaction
    #   otherwise it will be released at the end of block.
    # @param shared [Boolean] - is lock shared or not.
    # @param id [Integer] - number that will be used in pair with lock number to perform advisory lock.
    def initialize(name, transaction: false, shared: false, id: nil)
      @name = name.to_sym
      @transaction = transaction
      @shared = shared
      @id = id
    end

    # @yield - call block when lock is acquired
    #   block must be passed if transaction argument is false.
    # @raise [ArgumentError] when lock name is invalid.
    # @return yield
    def lock(&block)
      with_logger do
        lock_number = name_to_number
        advisory_lock(lock_number, &block)
      end
    end

    private

    attr_reader :transaction, :shared, :name, :id

    def with_logger
      return yield if logger.nil? || !logger.respond_to?(:tagged)

      logger.tagged(self.class.to_s, name.inspect) { yield }
    end

    def advisory_lock(lock_number, &block)
      if transaction
        transaction_lock(lock_number, &block)
      else
        non_transaction_lock(lock_number, &block)
      end
    end

    def transaction_lock(lock_number)
      raise ArgumentError, 'block required when not within transaction' if !block_given? && !sql_caller_class.transaction_open?

      return perform_lock(lock_number) unless block_given?

      sql_caller_class.transaction do
        perform_lock(lock_number)
        yield
      end
    end

    def non_transaction_lock(lock_number)
      raise ArgumentError, 'block required on transaction: false' unless block_given?

      begin
        perform_lock(lock_number)
        yield
      ensure
        perform_unlock(lock_number)
      end
    end

    def perform_lock(lock_number)
      function_name = "pg_advisory#{'_xact' if transaction}_lock#{'_shared' if shared}"

      sql_caller_class.execute("SELECT #{function_name}(#{lock_number})")
    end

    def perform_unlock(lock_number)
      sql_caller_class.select_value("SELECT pg_advisory_unlock#{'_shared' if shared}(#{lock_number})")
    end

    # Converts lock name to number, because pg advisory lock functions accept only bigint numbers.
    # @return [String] lock number or two numbers delimited by comma.
    def name_to_number
      lock_number = _lock_names.fetch(name) do
        raise ArgumentError, "lock name #{name.inspect} is invalid, see #{self.class}::NAMES"
      end
      lock_number = Array.wrap(lock_number)
      lock_number.push(id) if id.present?
      raise ArgumentError, "can't use lock name #{name.inspect} with id" if lock_number.size > 2

      lock_number.join(', ')
    end

    def sql_caller_class
      return @sql_caller_class if defined?(@sql_caller_class)

      @sql_caller_class = _sql_caller_class.is_a?(String) ? _sql_caller_class.constantize : _sql_caller_class
    end
  end
end
