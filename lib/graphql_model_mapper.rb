require "graphql"
require "graphql_model_mapper/mapper_type"
require "graphql_model_mapper/custom_type"
require "graphql_model_mapper/mutation"
require "graphql_model_mapper/query"
require "graphql_model_mapper/resolve"
require "graphql_model_mapper/schema"
require "graphql_model_mapper/utility"
require "graphql_model_mapper/encryption"
require "graphql_model_mapper/version"
require 'graphql_model_mapper/railtie' if defined?(Rails)

module GraphqlModelMapper
  mattr_accessor :query_resolve_wrapper
  mattr_accessor :mutation_resolve_wrapper
  mattr_accessor :resolve_wrapper
  mattr_accessor :type_case
  mattr_accessor :nesting_strategy
  mattr_accessor :use_authorize
  mattr_accessor :max_page_size
  mattr_accessor :scan_for_polymorphic_associations
  mattr_accessor :default_nodes_field
  mattr_accessor :bidirectional_pagination
  mattr_accessor :handle_errors
  mattr_accessor :secret_token
  mattr_accessor :encrypted_items
  
  

  @@type_case = :camelize
  @@nesting_strategy = :shallow
  @@use_authorize = false
  @@max_page_size = 100
  @@scan_for_polymorphic_associations = false
  @@query_resolve_wrapper = nil
  @@mutation_resolve_wrapper = nil
  @@default_nodes_field = false
  @@bidirectional_pagination = false
  @@handle_errors = true
  @@secret_token = nil
  @@encrypted_items = true
  

  class << self
    attr_writer :logger

    def logger
      @logger ||= Logger.new($stdout).tap do |log|
        log.progname = self.name
      end
    end
  end

  
  def self.included(klazz)
    klazz.extend GraphqlModelMapper_Macros
  end

  module GraphqlModelMapper_Macros

    protected
    
    def graphql_types(input_type:{}, output_type:{})
      define_singleton_method(:graphql_types) do
        GraphqlModelMapper::MapperType.graphql_types(name: self.name, input_type: input_type, output_type: output_type)
      end
    end

    def graphql_update(description:"", resolver: nil)
      define_singleton_method(:graphql_update) do
        resolver = resolver || -> (obj, inputs, ctx){
          item = GraphqlModelMapper::Resolve.update_resolver(obj, inputs, ctx, name)
          {
            item: item
          }
        }
        GraphqlModelMapper::Mutation.graphql_update(name: self.name, description: description, resolver: resolver)
      end
    end
    
    def graphql_delete(description:"", resolver: nil, arguments: [], scope_methods: [])
      define_singleton_method(:graphql_delete) do
        resolver = resolver || -> (obj, inputs, ctx){
          items = GraphqlModelMapper::Resolve.delete_resolver(obj, inputs, ctx, name)
          {
            items: items
          }
        }
        GraphqlModelMapper::Mutation.graphql_delete(name: self.name, description: description, resolver: resolver, scope_methods: scope_methods)
      end
    end
    
    def graphql_create(description:"", resolver: nil) 
      define_singleton_method(:graphql_create) do
        resolver = resolver || -> (obj, args, ctx){
          item = GraphqlModelMapper::Resolve.create_resolver(obj, args, ctx, name)
          {
            item: item
          }
        }
        GraphqlModelMapper::Mutation.graphql_create(name: self.name, description: description, resolver: resolver)
      end
    end

    def graphql_query(description: "", resolver: nil, arguments: [], scope_methods: [])
      #name = self.name
      define_singleton_method(:graphql_query) do
        resolver = resolver || -> (obj, args, ctx) {              
          items = GraphqlModelMapper::Resolve.query_resolver(obj, args, ctx, name)
        }
        GraphqlModelMapper::Query.graphql_query(name: self.name, description: description, resolver: resolver, scope_methods: scope_methods, arguments: arguments)
      end
    end
  end
end

ActiveRecord::Base.send(:include, GraphqlModelMapper) if defined?(ActiveRecord)