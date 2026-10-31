lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "ruboty/bundler/version"

Gem::Specification.new do |spec|
  spec.name          = "ruboty-bundler"
  spec.version       = Ruboty::Bundler::VERSION
  spec.authors       = ["Ryo Nakamura"]
  spec.email         = ["r7kamura@gmail.com"]
  spec.summary       = "Ruboty plug-in to manage Gemfile on GitHub repository"
  spec.homepage      = "https://github.com/r7kamura/ruboty"
  spec.license       = "MIT"
  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.3"

  spec.add_dependency "ruboty", ">= 1.2.1"
  spec.add_dependency "ruboty-github"
  spec.add_development_dependency "rake"
end
