require 'rspec/core/rake_task'
require 'bundler/gem_tasks'

task :default => [:test]

desc "Run all tests"
RSpec::Core::RakeTask.new(:test) do |t|
  t.rspec_opts = '-cfs'
end
