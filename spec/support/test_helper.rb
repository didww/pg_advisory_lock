# frozen_string_literal: true

module TestHelper
  def within_transaction?
    @within_transaction
  end

  # After call #within_transaction? will be true inside PgSqlCaller::Base.transaction block during test.
  def spy_transaction!
    @within_transaction = nil
    allow(TestSqlCaller).to receive(:transaction).and_wrap_original do |meth, *args, &block|
      @within_transaction = true
      meth.call(*args, &block)
    ensure
      @within_transaction = false
    end
  end

  # Allows to execute block before method actually executed
  # @yield arguments of method call
  def spy_method(object, meth, args = [no_args], opts = {}, &block)
    matcher = receive(meth).with(*args).exactly(opts[:times]).and_wrap_original do |orig_meth, *orig_args, &orig_block|
      block.call(*orig_args)
      orig_meth.call(*orig_args, &orig_block)
    end

    expect(object).to(matcher)
  end
end
