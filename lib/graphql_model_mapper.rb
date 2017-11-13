require "graphql"
require "graphql_model_mapper/mapper_type"
require "graphql_model_mapper/mutation"
require "graphql_model_mapper/query"
require "graphql_model_mapper/resolve"
require "graphql_model_mapper/schema"
require "graphql_model_mapper/version"

module GraphqlModelMapper
  mattr_accessor :type_suffix
  mattr_accessor :type_prefix
  mattr_accessor :type_case
  mattr_accessor :nesting_strategy
  mattr_accessor :use_authorize
  
  @@type_suffix = "_"
  @@type_prefix = ""
  @@type_case = :camelize
  @@nesting_strategy = :shallow
  @@use_authorize = false
  
  def self.included(klazz)
    klazz.extend GraphqlModelMapper_Macros
  end

  module GraphqlModelMapper_Macros
    protected

    def graphql_types(name: self.name, query: {}, update: {}, delete: {}, create: {})
      define_singleton_method(:graphql_types) do
        GraphqlModelMapper::MapperType.graphql_types(name: name, query: query, update: update, delete: delete, create: create)
      end
    end

    def graphql_update(name: self.name, description:"", resolver: nil)
      define_singleton_method(:graphql_update) do
        GraphqlModelMapper::Mutation.graphql_update(name: name, description: description, resolver: resolver)
      end
    end
    
    def graphql_delete(name: self.name, description:"", resolver: nil, arguments: [], scope_methods: [])
      define_singleton_method(:graphql_delete) do
        GraphqlModelMapper::Mutation.graphql_delete(name: name, description: description, resolver: resolver, scope_methods: scope_methods)
      end
    end
    
    def graphql_create(name: self.name, description:"", resolver: nil) 
      define_singleton_method(:graphql_create) do
        GraphqlModelMapper::Mutation.graphql_delete(name: name, description: description, resolver: resolver)
      end
    end

    def graphql_query(name: self.name, description: "", resolver: nil, arguments: [], scope_methods: [])                      
      define_singleton_method(:graphql_query) do
        GraphqlModelMapper::Query.graphql_query(name: name, description: description, resolver: resolver, scope_methods: scope_methods)
      end
    end
  end

  def self.implementations
    Rails.application.eager_load!
    ActiveRecord::Base.descendants.each.select do |clz|
      begin
        clz.included_modules.include?(GraphqlModelMapper) && (clz.public_methods.include?(:graphql_query) || clz.public_methods.include?(:graphql_update) || clz.public_methods.include?(:graphql_delete) || clz.public_methods.include?(:graphql_create) || clz.public_methods.include?(:graphql_types))
      rescue
        # it is okay that this is empty - just covering the possibility
      end
    end
  end

  def self.schema_queries
    fields = []
    GraphqlModelMapper.implementations.select{|t| t.public_methods.include?(:graphql_query)}.each { |t|      
      fields << { :name =>GraphqlModelMapper.get_type_case(t.name, false).to_sym, :field => t.graphql_query, :model_name=>t.name, :access_type=>:query }
    }
    fields
  end

  def self.schema_mutations
    fields = []
    GraphqlModelMapper.implementations.select{|t| t.public_methods.include?(:graphql_create)}.each { |t|
      fields << {:name => GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(t.name)}Create", false).to_sym, :field=> t.graphql_create, :model_name=>t.name, :access_type=>:create }
    }
    GraphqlModelMapper.implementations.select{|t| t.public_methods.include?(:graphql_update)}.each { |t|
      fields << {:name =>GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(t.name)}Update", false).to_sym, :field=>t.graphql_update, :model_name=>t.name, :access_type=>:update } 
    }
    GraphqlModelMapper.implementations.select{|t| t.public_methods.include?(:graphql_delete)}.each { |t|
      fields << {:name =>GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(t.name)}Delete", false).to_sym, :field=>t.graphql_delete, :model_name=>t.name, :access_type=>:delete }
    }
    fields
  end

  def self.select_list(model_name, classes=[])
    model = model_name.classify.constantize
    output = []
    columns = model.columns_hash.keys.map{|m| "#{model.name.underscore.pluralize}.#{m}"}
    relation_includes = model.reflect_on_all_associations.select{|t| begin t.klass rescue next end}.select{|t| !t.options[:polymorphic]}.map{|m| "#{model.name.underscore.pluralize}.#{m.name}"}
    relations = model.reflect_on_all_associations.select{|t| begin t.klass rescue next end}.select{|t| !t.options[:polymorphic]}
    relations.each do |a|
      if !classes.include?(a.klass.name)
        classes << a.klass.name
        output = output + GraphqlModelMapper.select_list(a.klass.name, classes)
      end
    end
    output << relation_includes + columns
    output.sort
  end

  def self.authorized?(ctx, model_name, access, roles=nil)
    model = model_name.classify.constantize
    access = access.to_sym
    #here it is checking to see if public methods are exposed on items based on the operation being performed
    if (access && access == :read) || (access && access == :query)
      access = :read 
      if !model.public_methods.include?(:graphql_query)
        return false
      end
    elsif access && access == :create
      if !model.public_methods.include?(:graphql_create)
        return false
      end
    elsif access && access == :update
      if !model.public_methods.include?(:graphql_update)
        return false
      end
    elsif access && access == :delete
      if !model.public_methods.include?(:graphql_delete)
        return false
      end
    end
    if roles && roles.length > 0
      roles.each do |r|
        if !ctx[:current_user].hash_role?(role)
          return false
        end
      end
    end
    #implementation specific, here it is using an ability method on the user class plugged into cancan
    if ctx[:current_user].public_methods.include?(:ability)
      if !ctx[:current_user].ability.can? access, model
        return false
      end
    end
    true
  end
 
  def self.get_type_name(classname, lowercase_first_letter=false)
    str = "#{GraphqlModelMapper.type_prefix}#{classname.classify.demodulize}#{GraphqlModelMapper.type_suffix}"
    if lowercase_first_letter && str.length > 0
      str = str[0].downcase + str[1..-1]
    end
    str
  end

  def self.get_type_case(str, uppercase=true)
    if @@type_case == :camelize
      if uppercase
        str.to_s.camelize(:upper)
      else
        str.to_s.camelize(:lower)
      end
    elsif @@type_case == :underscore
      if uppercase
        self.underscore(str)
      else
        str.underscore
      end
    else
      str
    end
  end

  def self.underscore(str, upcase=true)
    if upcase
      str.split('_').map {|w| w.capitalize}.join('_')
    else
      str.underscore
    end
  end

  def self.get_constant(type_name)
    GraphqlModelMapper.const_get(type_name.upcase)
  end

  def self.set_constant(type_name, type)
    GraphqlModelMapper.const_set(type_name.upcase, type)
  end

  def self.defined_constant?(type_name)
    GraphqlModelMapper.const_defined?(type_name.upcase)
  end
end

ActiveRecord::Base.send(:include, GraphqlModelMapper) if defined?(ActiveRecord)