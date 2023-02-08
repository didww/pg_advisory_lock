# frozen_string_literal: true

require 'yaml'
require 'active_support/logger'
require 'active_support/configuration_file'
require 'active_record'
require 'fileutils'

database_config_path = 'spec/config/database.yml'
database_config = ActiveSupport::ConfigurationFile.parse(database_config_path)
puts "#{database_config_path}:\n#{database_config.inspect}"
ActiveRecord::Base.establish_connection database_config['test']

if ENV['CI']
  ActiveRecord::Base.logger = ActiveSupport::Logger.new(STDOUT)
else
  FileUtils.mkdir_p 'tmp'
  ActiveRecord::Base.logger = ActiveSupport::Logger.new('tmp/test.log')
end

ActiveRecord::Base.logger.level = :debug
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  begin
    drop_table :employees
  rescue StandardError
    nil
  end
  begin
    drop_table :departments
  rescue StandardError
    nil
  end

  create_table :departments do |t|
    t.string :name, null: false
    t.timestamps null: false
  end

  create_table :employees do |t|
    t.integer :department_id, null: false
    t.string :name, null: false
    t.timestamps null: false
  end
end

class ApplicationRecord < ActiveRecord::Base
end

class Department < ApplicationRecord
  self.table_name = 'departments'
end

class Employee < ApplicationRecord
  self.table_name = 'employees'
  belongs_to :department, class_name: 'Department'
end
