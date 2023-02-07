# frozen_string_literal: true

RSpec.describe PgAdvisoryLock::Base do
  describe 'Transaction lock' do
    before do
      spy_transaction!

      expect(within_transaction?).to eq(nil)
      expect(TestSqlCaller.transaction_open?).to eq(false)
    end

    it 'with 1 number' do
      lock_sql = 'SELECT pg_advisory_xact_lock(1000)'
      spy_method(TestSqlCaller, :execute, [any_args], times: 1) do |*args|
        expect(args).to eq([lock_sql])
        expect(within_transaction?).to eq(true)
      end

      TestAdvisoryLock.with_lock(:test1) do
        expect(TestSqlCaller.transaction_open?).to eq(true)
      end

      expect(within_transaction?).to eq(false)
      expect(TestSqlCaller.transaction_open?).to eq(false)
    end

    it 'with shared' do
      lock_sql = 'SELECT pg_advisory_xact_lock_shared(1000)'
      spy_method(TestSqlCaller, :execute, [any_args], times: 1) do |*args|
        expect(args).to eq([lock_sql])
        expect(within_transaction?).to eq(true)
      end

      TestAdvisoryLock.with_lock(:test1, shared: true) do
        expect(TestSqlCaller.transaction_open?).to eq(true)
      end

      expect(within_transaction?).to eq(false)
      expect(TestSqlCaller.transaction_open?).to eq(false)
    end

    it 'with 2 numbers' do
      lock_sql = 'SELECT pg_advisory_xact_lock(1001, 1002)'
      spy_method(TestSqlCaller, :execute, [any_args], times: 1) do |*args|
        expect(args).to eq([lock_sql])
        expect(within_transaction?).to eq(true)
      end

      TestAdvisoryLock.with_lock(:test2) do
        expect(TestSqlCaller.transaction_open?).to eq(true)
      end

      expect(within_transaction?).to eq(false)
      expect(TestSqlCaller.transaction_open?).to eq(false)
    end

    it 'with number and id' do
      lock_sql = 'SELECT pg_advisory_xact_lock(1000, 123)'
      spy_method(TestSqlCaller, :execute, [any_args], times: 1) do |*args|
        expect(args).to eq([lock_sql])
        expect(within_transaction?).to eq(true)
      end

      TestAdvisoryLock.with_lock(:test1, id: 123) do
        expect(TestSqlCaller.transaction_open?).to eq(true)
      end

      expect(within_transaction?).to eq(false)
      expect(TestSqlCaller.transaction_open?).to eq(false)
    end

    it 'with number and string id' do
      id = '192.168.0.1'
      lock_sql = "SELECT pg_advisory_xact_lock(1000, hashtext('#{id}'))"
      spy_method(TestSqlCaller, :execute, [any_args], times: 1) do |*args|
        expect(args).to eq([lock_sql])
        expect(within_transaction?).to eq(true)
      end

      TestAdvisoryLock.with_lock(:test1, id: id) do
        expect(TestSqlCaller.transaction_open?).to eq(true)
      end

      expect(within_transaction?).to eq(false)
      expect(TestSqlCaller.transaction_open?).to eq(false)
    end

    it 'with 2 threads using #with_lock' do
      first_lock = nil
      second_lock = nil

      Thread.new do
        TestAdvisoryLock.with_lock(:test1) do
          first_lock = 'locked'
          sleep 2
        end
        first_lock = 'unlocked'
      end

      sleep 1 # wait for first thread to acquire lock

      first_lock_during_second_lock = nil
      Thread.new do
        TestAdvisoryLock.with_lock(:test1) do
          second_lock = 'locked'
          sleep 0.1
          # we can't write expectations in a thread, because we will not see failure message
          first_lock_during_second_lock = first_lock
        end
        second_lock = 'unlocked'
      end

      sleep 0.2 # wait second thread to start acquiring lock (and blocked in waiting mode)

      expect(first_lock).to eq('locked')
      expect(second_lock).to be_nil

      sleep 1 # wait both locks are unlocked (sleep total 2.2 > lock duration total 2.1)

      expect(first_lock).to eq('unlocked')
      expect(second_lock).to eq('unlocked')
      expect(first_lock_during_second_lock).to eq('unlocked') # first lock must be already unlocked when second_lock locked.
    end

    it 'with 2 threads using #try_lock', :aggregate_failures do
      first_lock = nil
      second_lock = nil

      Thread.new do
        TestAdvisoryLock.try_lock(:test1) do
          first_lock = 'locked'
          sleep 2
        end
        first_lock = 'unlocked'
      end

      sleep 1 # wait for first thread to acquire lock

      first_lock_during_second_lock = nil
      second_error = nil
      Thread.new do
        TestAdvisoryLock.try_lock(:test1) do
          second_lock = 'locked'
        end
        second_lock = 'unlocked'
      rescue PgAdvisoryLock::LockNotObtained => e
        second_lock = 'lock_not_obtained'
        # we can't write expectations in a thread, because we will not see failure message
        second_error = e.message
        first_lock_during_second_lock = first_lock
      end

      sleep 0.2 # wait second thread to try acquiring lock and fail

      expect(first_lock).to eq('locked')
      expect(second_lock).to eq('lock_not_obtained')

      sleep 1 # wait both locks are unlocked (sleep total 2.2 > lock duration total 2.0)

      expect(first_lock).to eq('unlocked')
      expect(second_lock).to eq('lock_not_obtained')
      expect(first_lock_during_second_lock).to eq('locked') # first lock must be still locked during second lock try.
      expect(second_error).to eq "TestAdvisoryLock can't obtain lock (test1, nil)"
    end
  end
end
