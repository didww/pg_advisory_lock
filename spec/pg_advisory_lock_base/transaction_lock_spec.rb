# frozen_string_literal: true

RSpec.describe PgAdvisoryLock::Base do
  describe 'Transaction lock' do
    before do
      spy_transaction!

      expect(within_transaction?).to eq(nil)
      expect(PgSqlCaller::Base.transaction_open?).to eq(false)
    end

    it 'with 1 number' do
      lock_sql = 'SELECT pg_advisory_xact_lock(1000)'
      spy_method(PgSqlCaller::Base, :execute, [any_args], times: 1) do |*args|
        expect(args).to eq([lock_sql])
        expect(within_transaction?).to eq(true)
      end

      PgAdvisoryLock::Base.with_lock(:test1, transaction: true) do
        expect(PgSqlCaller::Base.transaction_open?).to eq(true)
      end

      expect(within_transaction?).to eq(false)
      expect(PgSqlCaller::Base.transaction_open?).to eq(false)
    end

    it 'with shared' do
      lock_sql = 'SELECT pg_advisory_xact_lock_shared(1000)'
      spy_method(PgSqlCaller::Base, :execute, [any_args], times: 1) do |*args|
        expect(args).to eq([lock_sql])
        expect(within_transaction?).to eq(true)
      end

      PgAdvisoryLock::Base.with_lock(:test1, shared: true, transaction: true) do
        expect(PgSqlCaller::Base.transaction_open?).to eq(true)
      end

      expect(within_transaction?).to eq(false)
      expect(PgSqlCaller::Base.transaction_open?).to eq(false)
    end

    it 'with 2 numbers' do
      lock_sql = 'SELECT pg_advisory_xact_lock(1001, 1002)'
      spy_method(PgSqlCaller::Base, :execute, [any_args], times: 1) do |*args|
        expect(args).to eq([lock_sql])
        expect(within_transaction?).to eq(true)
      end

      PgAdvisoryLock::Base.with_lock(:test2, transaction: true) do
        expect(PgSqlCaller::Base.transaction_open?).to eq(true)
      end

      expect(within_transaction?).to eq(false)
      expect(PgSqlCaller::Base.transaction_open?).to eq(false)
    end

    it 'with number and id' do
      lock_sql = 'SELECT pg_advisory_xact_lock(1000, 123)'
      spy_method(PgSqlCaller::Base, :execute, [any_args], times: 1) do |*args|
        expect(args).to eq([lock_sql])
        expect(within_transaction?).to eq(true)
      end

      PgAdvisoryLock::Base.with_lock(:test1, id: 123, transaction: true) do
        expect(PgSqlCaller::Base.transaction_open?).to eq(true)
      end

      expect(within_transaction?).to eq(false)
      expect(PgSqlCaller::Base.transaction_open?).to eq(false)
    end
  end
end
