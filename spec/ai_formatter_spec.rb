# frozen_string_literal: true

require 'rspec/ai_formatter'

RSpec.describe RSpec::AiFormatter do
  it 'has a version number' do
    expect(RSpec::AiFormatter::VERSION).not_to be_nil
  end

  it 'has a formatter class' do
    expect(RSpec::AiFormatter::Formatter).to be_a(Class)
  end
end
