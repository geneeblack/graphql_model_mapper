module GraphqlModelMapper

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

  def self.log_resolve(ctx, args, generate_error: false)
    ret_info = {}
    ret_info[:return_type] = ctx.type.to_s
    ret_info[:return_fields] = []
    ctx.type.fields.keys.each do |f|
      ret_info[:return_fields] << {field: f, field_type: ctx.type.fields[f].type.to_s}
    end
    ret_wrap = {}
    ret_wrap[:input] = args.to_h
    ret_wrap[:output] = ret_info
    GraphqlModelMapper.logger.info "***GraphqlModelMapper_resolver_info: #{{resolver_data: ret_wrap}}"
    GraphQL::ExecutionError.new("resolver info", options: {resolver_data: ret_wrap}) if generate_error
  end

  def self.authorized?(ctx, model_name, access=:read, roles=nil)
      
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
    if !GraphqlModelMapper.use_authorize
      return true
    end
    #implementation specific, here it is using an ability method on the user class plugged into cancan
    if ctx && ctx[:current_user].public_methods.include?(:ability)
      if !ctx[:current_user].ability.can? access, model
        return false
      end
    end
    true
  end
 
  def self.get_type_name(classname, lowercase_first_letter=false)
    str = "#{classname.classify.demodulize}"
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
    elsif @@type_case == :classify
      str
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