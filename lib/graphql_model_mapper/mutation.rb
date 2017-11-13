module GraphqlModelMapper
    module Mutation
        def self.graphql_update(name: "",description:"",
            resolver: nil)
      
      
            input_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_key: :update, type_sub_key: :input_type)
            output_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_key: :update, type_sub_key: :output_type)
      
            self.get_mutation(name, description, "Update", resolver, input_type, output_type, name.downcase, "item")
          end
          
          def self.graphql_delete(name: "", description:"",
            resolver: nil,
            arguments: [],
            scope_methods: [])
            
            input_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_key: :delete, type_sub_key: :input_type)
            output_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_key: :delete, type_sub_key: :output_type).to_list_type
            self.get_delete_mutation(name, description, "Delete", resolver, arguments, scope_methods, input_type, output_type)
          end
          
          def self.graphql_create(name: "", description:"",
            resolver: nil)
            
            input_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_key: :create, type_sub_key: :input_type)
            output_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_key: :create, type_sub_key: :output_type)
      
            self.get_mutation(name, description, "Create", resolver, input_type, output_type, name.downcase, "item")
          end

          def self.get_mutation(name, description, operation_name, resolver, input_type, output_type, input_name, output_name)
            mutation_type_name = GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(name)}#{operation_name}")
            return GraphqlModelMapper.get_constant(mutation_type_name) if GraphqlModelMapper.defined_constant?(mutation_type_name)
            mutation_type = GraphQL::Relay::Mutation.define do
              name mutation_type_name
              description description
              input_field input_name.to_sym, -> {input_type}
              return_field output_name.to_sym, -> {output_type}
        
              resolve resolver
            end
        
            GraphqlModelMapper.set_constant(mutation_type_name, mutation_type.field)
            GraphqlModelMapper.get_constant(mutation_type_name)
        end

        def self.get_delete_mutation(name, description, operation_name, resolver, arguments, scope_methods, input_type, output_type)            
            query_type_name = GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(name)}#{operation_name}")
            return GraphqlModelMapper.get_constant(query_type_name) if GraphqlModelMapper.defined_constant?(query_type_name) 
            
            model = name.classify.constantize
    
            default_arguments = self.get_default_select_arguments(model, scope_methods)
            select_input_type_name = GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(name)}SelectInput")     
            if GraphqlModelMapper.defined_constant?(select_input_type_name)
            query_input_object_type = GraphqlModelMapper.get_constant(select_input_type_name)
            else
            query_input_object_type = GraphQL::InputObjectType.define do
                name select_input_type_name
                default_arguments.each do |k|
                argument k[:name].to_sym, k[:type], k[:description], default_value: k[:default] 
                end
            end
            GraphqlModelMapper.set_constant(select_input_type_name, query_input_object_type)
            end
        
            
            ret_type = GraphQL::Relay::Mutation.define do
                name query_type_name
                #return_field :item, output_object_type
                return_field :items, output_type
                return_field :total, -> {GraphQL::INT_TYPE}
    
                #description description
                #input_field "input".to_sym, -> {input_object_type}
                input_field :select, -> {!query_input_object_type}
        
                resolve resolver 
            end
            GraphqlModelMapper.set_constant(query_type_name, ret_type.field)
            GraphqlModelMapper.get_constant(query_type_name)
        end

        def self.get_default_select_arguments(model, scope_methods)
            default_arguments = [
              {:name=>:explain,   :type=>GraphQL::BOOLEAN_TYPE, :default=>nil}, 
              {:name=>:id,    :type=>GraphQL::INT_TYPE, :default=>nil}, 
              {:name=>:ids,    :type=>GraphQL::INT_TYPE.to_list_type, :default=>nil}, 
              {:name=>:limit, :type=>GraphQL::INT_TYPE, :default=>50},
              {:name=>:offset, :type=>GraphQL::INT_TYPE, :default=>nil},
              {:name=>:order,   :type=>GraphQL::STRING_TYPE, :default=>nil}, 
              {:name=>:where, :type=>GraphQL::STRING_TYPE.to_list_type, :default=>nil}
            ]
        
            scope_methods = scope_methods.map(&:to_sym)                        
            #.select{|m| model.method(m.to_sym).arity == 0}
            if (model.public_methods - model.instance_methods - Object.methods - ActiveRecord::Base.methods).include?(:with_deleted)
              default_arguments << {:name=>:with_deleted, :type=>GraphQL::BOOLEAN_TYPE, :default=>false}
            end
            allowed_scope_methods = []
            if scope_methods.count > 0
              scope_methods.each do |s|
                #.select{|m| model.method(m.to_sym).arity == 0}
                allowed_scope_methods << s if (model.public_methods - model.instance_methods - Object.methods - ActiveRecord::Base.methods).include?(s)
              end
              if allowed_scope_methods.count > 0
                typename = GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(model.name)}Scope_Enum")
                if !GraphqlModelMapper.defined_constant?(typename)
                  enum_type = GraphQL::EnumType.define do
                    name typename
                    description "scope enum for #{GraphqlModelMapper.get_type_name(model.name)}"
                    allowed_scope_methods.sort.each do |s|
                      value(s, "")
                    end
                  end
                  GraphqlModelMapper.set_constant typename, enum_type
                end
                default_arguments << {:name=>:scope, :type=>GraphqlModelMapper.get_constant(typename), :default=>nil}
              end
            end
            default_arguments
        end          
    end
end    