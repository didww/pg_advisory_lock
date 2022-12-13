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

      PgAdvisoryLock::Base.with_lock(:test1) do
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

      PgAdvisoryLock::Base.with_lock(:test1, shared: true) do
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

      PgAdvisoryLock::Base.with_lock(:test2) do
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

      PgAdvisoryLock::Base.with_lock(:test1, id: 123) do
        expect(PgSqlCaller::Base.transaction_open?).to eq(true)
      end

      expect(within_transaction?).to eq(false)
      expect(PgSqlCaller::Base.transaction_open?).to eq(false)
    end

    it 'with 2 threads using #with_lock' do
      first_lock = nil
      second_lock = nil

      Thread.new do
        PgAdvisoryLock::Base.with_lock(:test1) do
          first_lock = 'locked'
          sleep 2
        end
        first_lock = 'unlocked'
      end

      sleep 1 # wait for first thread to acquire lock

      Thread.new do
        PgAdvisoryLock::Base.with_lock(:test1) do
          second_lock = 'locked'
          expect(first_lock).to eq('unlocked') # first lock must be already unlocked
          sleep 0.1
        end
        second_lock = 'unlocked'
      end

      sleep 0.2 # wait second thread to start acquiring lock (and blocked in waiting mode)

      expect(first_lock).to eq('locked')
      expect(second_lock).to be_nil

      sleep 1 # wait both locks are unlocked (sleep total 2.2 > lock duration total 2.1)

      expect(first_lock).to eq('unlocked')
      expect(second_lock).to eq('unlocked')
    end

    it 'with 2 threads using #try_lock' do
      first_lock = nil
      second_lock = nil

      Thread.new do
        PgAdvisoryLock::Base.try_lock(:test1) do
          first_lock = 'locked'
          sleep 2
        end
        first_lock = 'unlocked'
      end

      sleep 1 # wait for first thread to acquire lock

      Thread.new do
        begin
          PgAdvisoryLock::Base.try_lock(:test1) do
            second_lock = 'locked'
          end
          second_lock = 'unlocked'
        rescue PgAdvisoryLock::LockNotObtained => e
          second_lock = 'lock_not_obtained'
          expect(first_lock).to eq('locked') # first lock must be still locked
        end
      end

      sleep 0.2 # wait second thread to try acquiring lock and fail

      expect(first_lock).to eq('locked')
      expect(second_lock).to eq('lock_not_obtained')

      sleep 1 # wait both locks are unlocked (sleep total 2.2 > lock duration total 2.0)

      expect(first_lock).to eq('unlocked')
      expect(second_lock).to eq('lock_not_obtained')
    end
  end
end
