require "base64"
require "ruboty"
require "ruboty/github"
require "tempfile"
require "tmpdir"

module Ruboty
  module Handlers
    class Bundler < Base
      DEFAULT_GIT_REPOSITORY_PATH = "/tmp/app"
      DEFAULT_GITHUB_HOST = "github.com"
      NAMESPACE = Ruboty::Github::Actions::Base::NAMESPACE

      env :RUBOTY_BUNDLER_REPOSITORY, "Target repository name (e.g. r7kamura/kokodeikku_bot)"

      on(
        /add gem (?<gem_name>\S+)(?: (?<version>.+))?/,
        description: "Add gem",
        name: :add,
      )

      on(
        /delete gem (?<gem_name>.+)/,
        description: "Delete gem",
        name: :delete,
      )

      def add(message)
        if client = client_for(message.from_name)
          message.reply("Bundler started")
          response = client.contents(repository, path: "Gemfile")
          gemfile_content = Base64.decode64(response[:content])
          gemfile_lock_content = Base64.decode64(client.contents(repository, path: "Gemfile.lock")[:content])
          gems = Gems.new(gemfile: gemfile_content, gemfile_lock: gemfile_lock_content)
          gems.add(message[:gem_name], version: message[:version])
          gemfile_content = gems.to_s
          gemfile_sha = response[:sha]
          gemfile_lock_content = Install.new(gemfile_content).call
          gemfile_lock_sha = client.contents(repository, path: "Gemfile.lock")[:sha]
          commit_message = "Add #{message[:gem_name]} gem"
          client.update_contents(
            repository,
            "Gemfile",
            commit_message,
            gemfile_sha,
            gemfile_content,
          )
          client.update_contents(
            repository,
            "Gemfile.lock",
            commit_message,
            gemfile_lock_sha,
            gemfile_lock_content,
          )
          message.reply("Bundler finished")
        else
          message.reply("I don't know your GitHub access token")
        end
      rescue Errno::ENOENT
        message.reply("Failed to add gem")
      end

      # TODO
      def delete(message)
        if client = client_for(message.from_name)
        else
          message.reply("I don't know your GitHub access token")
        end
      end

      private

      # @return [Hash]
      def access_tokens_table
        robot.brain.data[NAMESPACE] ||= {}
      end

      def api_endpoint
        "https://#{github_host}/api/v3" if github_host
      end

      # @param username [String, nil]
      # @return [Octokit::Client, nil]
      def client_for(username)
        if access_token = access_tokens_table[username]
          Octokit::Client.new(
            {
              access_token: access_token,
              api_endpoint: api_endpoint,
              web_endpoint: web_endpoint,
            }.reject do |key, value|
              value.nil?
            end
          )
        end
      end

      def git_repository_path
        DEFAULT_GIT_REPOSITORY_PATH
      end

      def git_repository_url
        web_endpoint + ENV["RUBOTY_BUNDLER_REPOSITORY"]
      end

      def github_host
        ENV["GITHUB_HOST"]
      end

      def repository
        ENV["RUBOTY_BUNDLER_REPOSITORY"]
      end

      def web_endpoint
        "https://#{github_host || DEFAULT_GITHUB_HOST}/"
      end

      class DependencyView
        def initialize(dependency)
          @dependency = dependency
        end

        def to_s
          str = "gem #{arguments.join(', ')}"
        end

        private

        def arguments
          [gem_name, requirement].compact.map(&:inspect)
        end

        def gem_name
          @dependency.name
        end

        def requirement
          if @dependency.requirement.to_s != ">= 0"
            @dependency.requirement.to_s
          end
        end
      end

      class Gems
        # @param gemfile [String] Content of Gemfile
        # @param gemfile_lcok [String] Content of Gemfile.lock
        def initialize(gemfile: nil, gemfile_lock: nil)
          @gemfile = gemfile
          @gemfile_lock = gemfile_lock
        end

        def add(gem_name, version: nil)
          dependencies.reject! do |dependency|
            dependency.name == gem_name
          end
          dependencies << ::Bundler::Dependency.new(gem_name, version || ">= 0")
        end

        # @return [String] Valid Gemfile content
        def to_s
          %<source "https://rubygems.org"\n\n> +
          dependencies.map do |dependency|
            DependencyView.new(dependency).to_s
          end.join("\n")
        end

        private

        def dependencies
          @dependencies ||= ::Bundler::Dsl.evaluate(
            gemfile_file.path,
            gemfile_lock_file.path,
            {},
          ).dependencies
        end

        def gemfile_file
          @gemfile_file ||= Tempfile.new("Gemfile").tap do |file|
            file.write(@gemfile)
            file.flush
          end
        end

        def gemfile_lock_file
          @gemfile_lock_file ||= Tempfile.new("Gemfile.lock").tap do |file|
            file.write(@gemfile_lock)
            file.flush
          end
        end
      end

      class Install
        # @param gemfile_content [String] Content of Gemfile.
        def initialize(gemfile_content)
          @gemfile_content = gemfile_content
        end

        # @return [String] Content of Gemfile.lock.
        def call
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              File.write("Gemfile", @gemfile_content)
              ::Bundler.with_clean_env do
                Ruboty.logger.debug(`bundle install`)
              end
              File.read("Gemfile.lock")
            end
          end
        end
      end
    end
  end
end
