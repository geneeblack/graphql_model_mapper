
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "graphql_model_mapper/version"

Gem::Specification.new do |spec|
  spec.name          = "graphql_model_mapper"
  spec.version       = GraphqlModelMapper::VERSION
  spec.authors       = ["Gene Black"]
  spec.email         = ["geblack@hotmail.com"]

  spec.summary       = %q{Adds GraphQL object generation based on your ActiveRecord models.}
  spec.description   = %q{This gem extends ActiveRecord::Base to add automatic generation of GraphQL objects based on your models.}
  spec.homepage      = "https://github.com/geneeblack/graphql_model_mapper"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.1'
  spec.add_runtime_dependency "graphql", ['>= 1.7.5']
  spec.add_runtime_dependency "graphql-errors", ['>= 0.1.0']
  spec.add_runtime_dependency "activesupport", ['>= 3.2.22.5']
  spec.add_runtime_dependency "activemodel", ['>= 3.2.22.5']
  spec.add_runtime_dependency "activerecord", ['>= 3.2.22.5']
  spec.add_runtime_dependency "rails", ['>= 3.2.22.5']
  spec.add_development_dependency "graphql", [">= 1.7.5"]
  spec.add_development_dependency "graphql-errors", ['>= 0.1.0']
  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
