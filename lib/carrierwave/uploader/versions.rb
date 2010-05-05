# encoding: utf-8

module CarrierWave
  module Uploader
    module Versions
      extend ActiveSupport::Concern

      include CarrierWave::Uploader::Callbacks

      included do
        after :cache, :cache_versions!
        after :store, :store_versions!
        after :remove, :remove_versions!
        after :retrieve_from_cache, :retrieve_versions_from_cache!
        after :retrieve_from_store, :retrieve_versions_from_store!
        
      end

      module ClassMethods

        def version_names
          @version_names ||= []
        end
        
        def version_conditions
          @version_conditions ||= {}
        end
        

        ##
        # Adds a new version to this uploader
        #
        # === Parameters
        #
        # [name (#to_sym)] name of the version
        # [&block (Proc)] a block to eval on this version of the uploader
        #
        def version(name, options = {}, &block)
          name = name.to_sym
          unless versions[name]
            versions[name] = Class.new(self)
            versions[name].version_names.push(*version_names)
            versions[name].version_names.push(name)
            version_conditions[name] = options
            class_eval <<-RUBY
              def #{name}
                versions[:#{name}]
              end
            RUBY
          end
          versions[name].class_eval(&block) if block
          versions[name]
        end

        ##
        # === Returns
        #
        # [Hash{Symbol => Class}] a list of versions available for this uploader
        #
        def versions
          @versions ||= {}
        end

      end # ClassMethods

      ##
      # Returns a hash mapping the name of each version of the uploader to an instance of it
      #
      # === Returns
      #
      # [Hash{Symbol => CarrierWave::Uploader}] a list of uploader instances
      #
      def versions
        return @versions if @versions
        @versions = {}
        self.class.versions.each do |name, klass|
          @versions[name] = klass.new(model, mounted_as)
        end
        @versions
      end
      
      def version_conditions
        return @version_conditions if @version_conditions
        @version_conditions = {}
        self.class.version_conditions.each do |name, conditions|
          @version_conditions[name] = conditions
        end
        @version_conditions
      end

      ##
      # === Returns
      #
      # [String] the name of this version of the uploader
      #
      def version_name
        self.class.version_names.join('_').to_sym unless self.class.version_names.blank?
      end

      ##
      # When given a version name as a parameter, will return the url for that version
      # This also works with nested versions.
      #
      # === Example
      #
      #     my_uploader.url                 # => /path/to/my/uploader.gif
      #     my_uploader.url(:thumb)         # => /path/to/my/thumb_uploader.gif
      #     my_uploader.url(:thumb, :small) # => /path/to/my/thumb_small_uploader.gif
      #
      # === Parameters
      #
      # [*args (Symbol)] any number of versions
      #
      # === Returns
      #
      # [String] the location where this file is accessible via a url
      #
      def url(*args)
        if(args.first)
          raise ArgumentError, "Version #{args.first} doesn't exist!" if versions[args.first.to_sym].nil?
          # recursively proxy to version
          versions[args.first.to_sym].url(*args[1..-1])
        else
          super()
        end
      end

      ##
      # Recreate versions and reprocess them. This can be used to recreate
      # versions if their parameters somehow have changed.
      #
      def recreate_versions!
        with_callbacks(:recreate_versions, file) do
          versions.each { |name, v| v.store!(file) }
        end
      end

    private
      

      def full_filename(for_file)
        [version_name, super(for_file)].compact.join('_')
      end

      def full_original_filename
        [version_name, super].compact.join('_')
      end
      
      def cache_versions!(new_file)
        versions.each do |name, v|
          if satisfies_version_requirements!(name, new_file)
            v.send(:cache_id=, cache_id)
            v.cache!(new_file)
          end
        end
      end
      
      def store_versions!(new_file)
        versions.each do |name, v| 
          v.store!(new_file) if satisfies_version_requirements!(name, new_file)
        end
      end

      def remove_versions!
        versions.each { |name, v| v.remove! }
      end
      
      def retrieve_versions_from_cache!(cache_name)
        versions.each do |name, v| 
          v.retrieve_from_cache!(cache_name) if satisfies_version_requirements!(name)
        end
      end

      def retrieve_versions_from_store!(identifier)
        versions.each do |name, v| 
          v.retrieve_from_store!(identifier) if satisfies_version_requirements!(name)
        end
      end
      
      def satisfies_version_requirements!(name, new_file = nil, remove = true)
        file_to_check = new_file.nil? ? file : new_file
        if version_conditions[name] && version_conditions[name][:if]
          cond = version_conditions[name][:if]
          if cond.call(file_to_check)
            return true
          else
            versions.delete(name) if remove
            return false
          end
        else
          true
        end
      end

    end # Versions
  end # Uploader
end # CarrierWave
