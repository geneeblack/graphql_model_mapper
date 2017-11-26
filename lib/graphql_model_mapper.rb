require "graphql"
require "graphql_model_mapper/mapper_type"
require "graphql_model_mapper/custom_type"
require "graphql_model_mapper/mutation"
require "graphql_model_mapper/query"
require "graphql_model_mapper/resolve"
require "graphql_model_mapper/schema"
require "graphql_model_mapper/utility"
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
  

  @@type_case = :camelize
  @@nesting_strategy = :shallow
  @@use_authorize = false
  @@max_page_size = 100
  @@scan_for_polymorphic_associations = false
  @@query_resolve_wrapper = nil
  @@mutation_resolve_wrapper = nil
  @@default_nodes_field = false
  @@bidirectional_pagination = false
  @@handle_errors = false
  


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
      name = self.name
      define_singleton_method(:graphql_types) do
        GraphqlModelMapper::MapperType.graphql_types(name: name, input_type: input_type, output_type: output_type)
      end
    end

    def graphql_update(description:"", resolver: -> (obj, inputs, ctx){
        item = GraphqlModelMapper::Resolve.update_resolver(obj, inputs, ctx, name)
        {
          item: item
        }
      })
      name = self.name
      define_singleton_method(:graphql_update) do
        GraphqlModelMapper::Mutation.graphql_update(name: name, description: description, resolver: resolver)
      end
    end
    
    def graphql_delete(description:"", resolver: -> (obj, inputs, ctx){
        items = GraphqlModelMapper::Resolve.delete_resolver(obj, inputs, ctx, name)
        {
          items: items
        }
      }, arguments: [], scope_methods: [])
      name = self.name
      define_singleton_method(:graphql_delete) do
        GraphqlModelMapper::Mutation.graphql_delete(name: name, description: description, resolver: resolver, scope_methods: scope_methods)
      end
    end
    
    def graphql_create(description:"", resolver:  -> (obj, args, ctx){
        item = GraphqlModelMapper::Resolve.create_resolver(obj, args, ctx, name)
        {
          item: item
        }
      }) 
      name = self.name
      define_singleton_method(:graphql_create) do
        GraphqlModelMapper::Mutation.graphql_create(name: name, description: description, resolver: resolver)
      end
    end

    def graphql_query(description: "", resolver: -> (obj, args, ctx) {              
        items = GraphqlModelMapper::Resolve.query_resolver(obj, args, ctx, name)
      }, arguments: [], scope_methods: [])                      
      name = self.name
      define_singleton_method(:graphql_query) do
        GraphqlModelMapper::Query.graphql_query(name: name, description: description, resolver: resolver, scope_methods: scope_methods, arguments: arguments)
      end
    end
  end
end

ActiveRecord::Base.send(:include, GraphqlModelMapper) if defined?(ActiveRecord)