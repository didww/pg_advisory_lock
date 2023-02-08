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
        raise ArgumentError, 'value must be integer or array of integers' unless int_or_array_of_ints?(value)

        _lock_names[name.to_sym] = value
      end

      # @param klass [Class<PgSqlCaller::Base>, String]
      def sql_caller_class(klass)
        self._sql_caller_class = klass
      end

      # Locks specific advisory lock.
      # If it's already locked just waits.
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
        new(name, transaction: transaction, shared: shared, id: id, wait: true).lock(&block)
      end

      # Tries to lock specific advisory lock.
      # If it's already locked raises exception.
      # @param name [Symbol, String] - lock name (will be transformed to number).
      # @param transaction [Boolean] - if true lock will be released at the end of current transaction
      #   otherwise it will be released at the end of block.
      # @param shared [Boolean] - is lock shared or not.
      # @param id [Integer] - number that will be used in pair with lock number to perform advisory lock.
      # @yield - call block when lock is acquired
      #   block must be passed if transaction argument is false.
      # @raise [ArgumentError] when lock name is invalid.
      # @raise [PgAdvisoryLock::LockNotObtained] when wait: false passed and lock already locked.
      # @return yield
      def try_lock(name, transaction: true, shared: false, id: nil, &block)
        new(name, transaction: transaction, shared: shared, id: id, wait: false).lock(&block)
      end

      private

      def int_or_array_of_ints?(value)
        return true if value.is_a?(Integer)

        return true if value.is_a?(Array) && value.all? { |i| i.is_a?(Integer) }

        false
      end
    end

    # @param name [Symbol, String] - lock name (will be transformed to number).
    # @param transaction [Boolean] - if true lock will be released at the end of current transaction
    #   otherwise it will be released at the end of block.
    # @param shared [Boolean] - is lock shared or not.
    # @param id [Integer] - number that will be used in pair with lock number to perform advisory lock.
    # @param wait [Boolean] - when locked by someone else: true - wait for lock, raise PgAdvisoryLock::LockNotObtained.
    def initialize(name, transaction:, shared:, id:, wait:)
      @name = name.to_sym
      @transaction = transaction
      @shared = shared
      @id = id
      @wait = wait
    end

    # @yield - call block when lock is acquired
    #   block must be passed if transaction argument is false.
    # @raise [ArgumentError] when lock name is invalid.
    # @raise [PgAdvisoryLock::LockNotObtained] when wait: false passed and lock already locked.
    # @return yield
    def lock(&block)
      with_logger do
        lock_args = build_lock_args
        advisory_lock(lock_args, &block)
      end
    end

    private

    attr_reader :transaction, :shared, :name, :id, :wait

    def with_logger
      return yield if logger.nil? || !logger.respond_to?(:tagged)

      logger.tagged(self.class.to_s, name.inspect) { yield }
    end

    def advisory_lock(lock_args, &block)
      if transaction
        transaction_lock(lock_args, &block)
      else
        non_transaction_lock(lock_args, &block)
      end
    end

    def transaction_lock(lock_args)
      raise ArgumentError, 'block required when not within transaction' if !block_given? && !sql_caller_class.transaction_open?

      return perform_lock(lock_args) unless block_given?

      sql_caller_class.transaction do
        perform_lock(lock_args)
        yield
      end
    end

    def non_transaction_lock(lock_args)
      raise ArgumentError, 'block required on transaction: false' unless block_given?

      begin
        perform_lock(lock_args)
        yield
      ensure
        perform_unlock(lock_args)
      end
    end

    def perform_lock(lock_args)
      function_name = "pg#{'_try' unless wait}_advisory#{'_xact' if transaction}_lock#{'_shared' if shared}"

      if wait
        sql_caller_class.execute("SELECT #{function_name}(#{lock_args})")
      else
        result = sql_caller_class.select_value("SELECT #{function_name}(#{lock_args})")
        raise LockNotObtained, "#{self.class} can't obtain lock (#{name}, #{id.inspect})" unless result
      end
    end

    def perform_unlock(lock_args)
      sql_caller_class.select_value("SELECT pg_advisory_unlock#{'_shared' if shared}(#{lock_args})")
    end

    # Converts lock name to number, because pg advisory lock functions accept only bigint numbers.
    # @return [String] lock number or two numbers delimited by comma.
    def build_lock_args
      lock_args = _lock_names.fetch(name) do
        raise ArgumentError, "lock name #{name.inspect} is invalid, see #{self.class}::NAMES"
      end
      lock_args = Array.wrap(lock_args)
      if id.present?
        if id.is_a?(Integer)
          lock_args.push(id)
        else
          lock_args.push("hashtext(#{sql_caller_class.connection.quote(id.to_s)})")
        end
      end
      raise ArgumentError, "can't use lock name #{name.inspect} with id" if lock_args.size > 2

      lock_args.join(', ')
    end

    def sql_caller_class
      return @sql_caller_class if defined?(@sql_caller_class)

      @sql_caller_class = _sql_caller_class.is_a?(String) ? _sql_caller_class.constantize : _sql_caller_class
    end
  end
end
