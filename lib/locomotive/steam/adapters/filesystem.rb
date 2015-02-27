require_relative 'memory'

require_relative 'filesystem/simple_cache_store'

require_relative 'filesystem/yaml_loader'
require_relative 'filesystem/yaml_loaders/site'
require_relative 'filesystem/yaml_loaders/page'
require_relative 'filesystem/yaml_loaders/snippet'
require_relative 'filesystem/yaml_loaders/translation'
require_relative 'filesystem/yaml_loaders/theme_asset'

require_relative 'filesystem/sanitizer'
require_relative 'filesystem/sanitizers/simple'
require_relative 'filesystem/sanitizers/page'
require_relative 'filesystem/sanitizers/snippet'

module Locomotive::Steam

  class FilesystemAdapter < Struct.new(:site_path)

    include Morphine
    include Locomotive::Steam::Adapters::Concerns::Key

    register :cache do
      Locomotive::Steam::Adapters::Filesystem::SimpleCacheStore.new
    end

    register(:yaml_loaders)  { build_yaml_loaders }
    register(:sanitizers)    { build_sanitizers }

    def all(mapper, scope)
      memoized_dataset(mapper, scope)
    end

    def query(mapper, scope, &block)
      _query(mapper, scope, &block).tap do |default|
        if scope.site
          default.where(site_id: scope.site._id)
        end
      end
    end

    def find(mapper, scope, id)
      _query(mapper, scope) { where(_id: id) }.first
    end

    def theme_assets_base_url(scope)
      ''
    end

    private

    def _query(mapper, scope, &block)
      Locomotive::Steam::Adapters::Memory::Query.new(all(mapper, scope), scope.locale, &block)
    end

    def memoized_dataset(mapper, scope)
      cache.fetch(mapper.name) do
        dataset(mapper, scope)
      end
    end

    def dataset(mapper, scope)
      Locomotive::Steam::Adapters::Memory::Dataset.new(mapper.name).tap do |dataset|
        populate_dataset(dataset, mapper, scope)
      end
    end

    def populate_dataset(dataset, mapper, scope)
      sanitizers[mapper.name].with(scope) do |sanitizer|
        collection(mapper, scope).each do |attributes|
          entity = mapper.to_entity(attributes)
          dataset.insert(entity)

          sanitizer.apply_to(entity)
        end

        sanitizer.apply_to(dataset)
      end
    end

    def collection(mapper, scope)
      yaml_loaders[mapper.name].load(scope)
    end

    def build_yaml_loaders
      %i(sites pages snippets translations theme_assets).inject({}) do |memo, name|
        memo[name] = build_klass('YAMLLoaders', name).new(site_path)
        memo
      end
    end

    def build_sanitizers
      hash = Hash.new { build_klass('Sanitizers', :simple).new }
      %i(pages snippets).inject(hash) do |memo, name|
        memo[name] = build_klass('Sanitizers', name).new
        memo
      end
    end

    def build_klass(type, name)
      _name = name.to_s.singularize.camelize
      "Locomotive::Steam::Adapters::Filesystem::#{type}::#{_name}".constantize
    end

  end

end


