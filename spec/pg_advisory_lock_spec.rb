# frozen_string_literal: true

RSpec.describe PgAdvisoryLock do
  it 'has a version number' do
    expect(PgAdvisoryLock::VERSION).not_to be nil
  end
end
