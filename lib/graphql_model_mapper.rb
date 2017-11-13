require "graphql"
require "graphql_model_mapper/mapper_type"
require "graphql_model_mapper/mutation"
require "graphql_model_mapper/query"
require "graphql_model_mapper/resolve"
require "graphql_model_mapper/schema"
require "graphql_model_mapper/utility"
require "graphql_model_mapper/version"
require 'graphql_model_mapper/railtie' if defined?(Rails)

module GraphqlModelMapper
  mattr_accessor :type_case
  mattr_accessor :nesting_strategy
  mattr_accessor :use_authorize

  @@type_case = :camelize
  @@nesting_strategy = :shallow
  @@use_authorize = false
  
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

    def graphql_types(query: {}, update: {}, delete: {}, create: {})
      name = self.name
      define_singleton_method(:graphql_types) do
        GraphqlModelMapper::MapperType.graphql_types(name: name, query: query, update: update, delete: delete, create: create)
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
          total: items.length,
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
        {
          items: items,
          total: items.length
        }
      }, arguments: [], scope_methods: [])                      
      name = self.name
      define_singleton_method(:graphql_query) do
        GraphqlModelMapper::Query.graphql_query(name: name, description: description, resolver: resolver, scope_methods: scope_methods)
      end
    end
  end
end

ActiveRecord::Base.send(:include, GraphqlModelMapper) if defined?(ActiveRecord)