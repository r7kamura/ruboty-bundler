require "base64"
require "ruboty"
require "ruboty/github"
require "tempfile"
require "tmpdir"

module Ruboty
  module Handlers
    class Bundler < Base
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
          gems = Gems.new(
            gemfile_content: Base64.decode64(client.get("Gemfile")[:content]),
            gemfile_lock_content: Base64.decode64(client.get("Gemfile.lock")[:content]),
          )
          gems.add(message[:gem_name], version: message[:version])
          gemfile_content = GemfileView.new(gems).to_s
          gemfile_lock_content = Install.new(gemfile_content).call
          client.update("Gemfile", gemfile_content)
          client.update("Gemfile.lock", gemfile_lock_content)
          message.reply("Bundler finished")
        else
          message.reply("I don't know your GitHub access token")
        end
      rescue Errno::ENOENT
        message.reply("Failed to add gem")
      end

      def delete(message)
        if client = client_for(message.from_name)
          message.reply("Bundler started")
          gems = Gems.new(
            gemfile_content: Base64.decode64(client.get("Gemfile")[:content]),
            gemfile_lock_content: Base64.decode64(client.get("Gemfile.lock")[:content]),
          )
          gems.delete(message[:gem_name])
          gemfile_content = GemfileView.new(gems).to_s
          gemfile_lock_content = Install.new(gemfile_content).call
          client.update("Gemfile", gemfile_content)
          client.update("Gemfile.lock", gemfile_lock_content)
          message.reply("Bundler finished")
        else
          message.reply("I don't know your GitHub access token")
        end
      rescue GemNotFound
        message.reply("Gem not found")
      rescue Errno::ENOENT
        message.reply("Failed to delete gem")
      end

      private

      # @return [Hash]
      def access_tokens_table
        robot.brain.data[NAMESPACE] ||= {}
      end

      # @param username [String, nil]
      # @return [Ruboty::Bundler::Client, nil]
      def client_for(username)
        if access_token = access_tokens_table[username]
          Client.new(access_token: access_token)
        end
      end

      class Client
        DEFAULT_GITHUB_HOST = "github.com"

        def initialize(access_token: nil)
          @access_token = access_token
        end

        # @param path [String] File path (e.g. "Gemfile")
        # @return [String] File content
        def get(path)
          cache[path] ||= octokit_client.contents(repository, path: path)
        end

        # @param path [String] File path (e.g. "Gemfile")
        # @param content [String] File content
        def update(path, content)
          octokit_client.update_contents(
            repository,
            path,
            "Update #{path}",
            get(path)[:sha],
            content,
          )
        end

        private

        def api_endpoint
          "https://#{github_host}/api/v3" if github_host
        end

        def cache
          @cache ||= {}
        end

        def github_host
          ENV["GITHUB_HOST"]
        end

        def octokit_client
          @octokit_client ||= Octokit::Client.new(
            {
              access_token: @access_token,
              api_endpoint: api_endpoint,
              web_endpoint: web_endpoint,
            }.reject do |key, value|
              value.nil?
            end
          )
        end

        def repository
          ENV["RUBOTY_BUNDLER_REPOSITORY"]
        end

        def web_endpoint
          "https://#{github_host || DEFAULT_GITHUB_HOST}/"
        end
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

      class GemfileView
        def initialize(gems)
          @gems = gems
        end

        def to_s
          %<source "https://rubygems.org"\n\n> +
          @gems.dependencies.map do |dependency|
            DependencyView.new(dependency).to_s
          end.join("\n")
        end
      end

      class GemNotFound < StandardError
      end

      class Gems
        # @param gemfile_content [String]
        # @param gemfile_lcok_content [String]
        def initialize(gemfile_content: nil, gemfile_lock_content: nil)
          @gemfile_content = gemfile_content
          @gemfile_lock_content = gemfile_lock_content
        end

        def add(gem_name, version: nil)
          dependencies.reject! do |dependency|
            dependency.name == gem_name
          end
          dependencies << ::Bundler::Dependency.new(gem_name, version || ">= 0")
        end

        def delete(gem_name)
          raise GemNotFound if dependencies.all? {|dependency| dependency.name != gem_name }
          dependencies.reject! do |dependency|
            dependency.name == gem_name
          end
        end

        def dependencies
          @dependencies ||= ::Bundler::Dsl.evaluate(
            gemfile_file.path,
            gemfile_lock_file.path,
            {},
          ).dependencies
        end

        private

        def gemfile_file
          @gemfile_file ||= Tempfile.new("Gemfile").tap do |file|
            file.write(@gemfile_content)
            file.flush
          end
        end

        def gemfile_lock_file
          @gemfile_lock_file ||= Tempfile.new("Gemfile.lock").tap do |file|
            file.write(@gemfile_lock_content)
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
                Ruboty.logger.debug(`bundle install --no-deployment`)
              end
              File.read("Gemfile.lock")
            end
          end
        end
      end
    end
  end
end
