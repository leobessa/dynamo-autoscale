require 'date'
require './lib/dynamo-autoscale/version'

Gem::Specification.new do |gem|
  gem.name    = 'dynamo-autoscale'
  gem.version = DynamoAutoscale::VERSION
  gem.date    = Date.today.to_s

  gem.summary = "Autoscaling for DynamoDB provisioned throughputs."
  gem.description = "Will automatically monitor DynamoDB tables and scale them based on rules."

  gem.authors  = ['InvisibleHand']
  gem.email    = 'developers@getinvisiblehand.com'
  gem.homepage = 'http://github.com/invisiblehand/dynamo-autoscale'

  gem.bindir      = ['bin']
  gem.executables = ['dynamo-autoscale']

  gem.license  = 'MIT'

  gem.required_ruby_version = '>= 1.9.3'

  gem.requirements << "If you want to graph your tables, you'll need R with " +
    "the ggplot and reshape packages installed."

  gem.add_dependency 'aws-sdk'
  gem.add_dependency 'rbtree'
  gem.add_dependency 'ruby-prof'
  gem.add_dependency 'colored'
  gem.add_dependency 'activesupport'
  gem.add_dependency 'pony'

  # ensure the gem is built out of versioned files
  gem.files = `git ls-files -z`.split("\0")
end
