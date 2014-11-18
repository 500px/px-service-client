# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'px_service/client/version'

Gem::Specification.new do |spec|
  spec.name          = "px-service-client"
  spec.version       = PxService::Client::VERSION
  spec.summary       = %q{Common service client behaviours for Ruby applications}
  spec.authors       = ["Chris Micacchi"]
  spec.email         = ["chris@500px.com"]
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "will_paginate", "~> 3.0"
  spec.add_dependency "dalli"
  spec.add_dependency "typhoeus"
  spec.add_dependency "activesupport", "~> 4.1"
  spec.add_dependency "circuit_breaker", "~> 1.1"

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "vcr"
  spec.add_development_dependency "guard"
  spec.add_development_dependency "guard-rspec"
  spec.add_development_dependency "rspec", "~> 2.14"
  spec.add_development_dependency "timecop", "~> 0.5"
end
