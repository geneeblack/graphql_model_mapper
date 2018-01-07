module GraphqlModelMapper
    module Mutation
        def self.graphql_update(name: "",description:"",
            resolver: nil)
      
            resolver = resolver || -> (obj, inputs, ctx){
              item = GraphqlModelMapper::Resolve.update_resolver(obj, inputs, ctx, name)
              {
                item: item
              }
            }
          
            input_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_sub_key: :input_type)
            output_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_sub_key: :output_type)
      
            self.get_mutation(name, description, "Update", resolver, input_type, output_type, name.downcase, "item")
          end
          
          def self.graphql_delete(name: "", description:"",
            resolver: nil,
            arguments: [],
            scope_methods: [])
            
            resolver = resolver || -> (obj, inputs, ctx){
              items = GraphqlModelMapper::Resolve.delete_resolver(obj, inputs, ctx, name)
              {
                items: items
              }
            }
            input_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_sub_key: :input_type)
            output_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_sub_key: :output_type).to_list_type
            self.get_delete_mutation(name, description, "Delete", resolver, arguments, scope_methods, input_type, output_type)
          end
          
          def self.graphql_create(name: "", description:"",
            resolver: nil)
            
            resolver = resolver || -> (obj, args, ctx){
              item = GraphqlModelMapper::Resolve.create_resolver(obj, args, ctx, name)
              {
                item: item
              }
            }
            input_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_sub_key: :input_type)
            output_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_sub_key: :output_type)
      
            self.get_mutation(name, description, "Create", resolver, input_type, output_type, name.downcase, "item")
          end

          def self.get_mutation(name, description, operation_name, resolver, input_type, output_type, input_name, output_name)
            model = name.classify.constantize
            mutation_type_name = GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(name)}#{operation_name}")
            return GraphqlModelMapper.get_constant(mutation_type_name) if GraphqlModelMapper.defined_constant?(mutation_type_name)
            mutation_type = GraphQL::Relay::Mutation.define do
              name mutation_type_name
              description description
              input_field input_name.to_sym, -> {input_type}
              return_field output_name.to_sym, -> {output_type}
        
              resolve GraphqlModelMapper::Mutation.get_resolver(resolver, model, operation_name.downcase.to_sym)
            end
        
            GraphqlModelMapper.set_constant(mutation_type_name, mutation_type.field)
            GraphqlModelMapper.get_constant(mutation_type_name)
        end

        def self.get_delete_mutation(name, description, operation_name, resolver, arguments, scope_methods, input_type, output_type)            
            query_type_name = GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(name)}#{operation_name}")
            return GraphqlModelMapper.get_constant(query_type_name) if GraphqlModelMapper.defined_constant?(query_type_name) 
            
            model = name.classify.constantize
            default_arguments = arguments ? (arguments.length > 0 ? arguments : self.get_default_select_arguments(model, scope_methods)) : []

            select_input_type_name = GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(name)}SelectInput")                                         
            if GraphqlModelMapper.defined_constant?(select_input_type_name)
              query_input_object_type = GraphqlModelMapper.get_constant(select_input_type_name)
            else
              query_input_object_type = GraphQL::InputObjectType.define do
                  name select_input_type_name
                  default_arguments.each do |k|
                    argument k[:name].to_sym, k[:type], k[:description], default_value: k[:default] do                  
                      if k[:authorization] && GraphqlModelMapper.use_authorize
                        authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_field_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true  }
                        model_name name
                        access_type k[:authorization] 
                      end       
                    end 
                  end
              end
              GraphqlModelMapper.set_constant(select_input_type_name, query_input_object_type)
            end
        
            total_result_type_name = GraphqlModelMapper.get_type_case("TotalResult")                                         
            if GraphqlModelMapper.defined_constant?(total_result_type_name)
              total_result_type = GraphqlModelMapper.get_constant(total_result_type_name)
            else
              total_result_type =  GraphQL::InterfaceType.define do
                name total_result_type_name
                field :totalCount, -> {GraphQL::INT_TYPE} do
                  resolve -> (obj, args, ctx) {
                    obj.items.length
                  }
                end
              end
              GraphqlModelMapper.set_constant(total_result_type_name, total_result_type)
            end

            
            ret_type = GraphQL::Relay::Mutation.define do
                name query_type_name
                return_field :items, output_type
                return_interfaces [total_result_type]
                input_field :select, -> {!query_input_object_type}

                resolve GraphqlModelMapper::Mutation.get_resolver(resolver, model, :delete) 
            end
            GraphqlModelMapper.set_constant(query_type_name, ret_type.field)
            GraphqlModelMapper.get_constant(query_type_name)
        end

        def self.get_default_select_arguments(model, scope_methods)
            default_arguments = [
              {:name=>:id,    :type=>GraphQL::ID_TYPE, :default=>nil}, 
              {:name=>:ids,    :type=>GraphQL::ID_TYPE.to_list_type, :default=>nil},
            ]

            default_arguments = default_arguments + [
              {:name=>:item_id,    :type=>GraphQL::INT_TYPE, :default=>nil}, 
              {:name=>:item_ids,    :type=>GraphQL::INT_TYPE.to_list_type, :default=>nil}
            ] if GraphqlModelMapper::MapperType.get_type_params(model.name, type_sub_key: :input_type)[:primary_keys]
        
            default_arguments = default_arguments + [
              {:name=>:explain,   :type=>GraphQL::BOOLEAN_TYPE, :default=>nil, :authorization=>:manage}, 
              {:name=>:order,   :type=>GraphQL::STRING_TYPE, :default=>nil, :authorization=>:manage}, 
              {:name=>:where, :type=>GraphQL::STRING_TYPE.to_list_type, :default=>nil, :authorization=>:manage }
            ]
  
            default_arguments = default_arguments + [
              {:name=>:short_filter, :type=>->{ GraphqlModelMapper::MapperType.get_ar_object(model.name, type_sub_key: :search_type)}},
              {:name=>:full_filter, :type=>->{ GraphqlModelMapper::MapperType.get_ar_object(model.name, type_sub_key: :search_type_full)}},
              {:name=>:order_by, :type=>->{ GraphqlModelMapper::MapperType.get_ar_object(model.name, type_sub_key: :order_type)}},
              {:name=>:order_by_full, :type=>->{ GraphqlModelMapper::MapperType.get_ar_object(model.name, type_sub_key: :order_type_full)}},
              {:name=>:includes, :type=>->{ GraphqlModelMapper::MapperType.get_ar_object(model.name, type_sub_key: :includes_type)}},
              {:name=>:joins, :type=>GraphQL::STRING_TYPE, :default=>nil, :authorization=>:manage}
            ]


            scope_methods = scope_methods.map(&:to_sym)                        
            #.select{|m| model.method(m.to_sym).arity == 0}
            if (model.public_methods - model.instance_methods - Object.methods - ActiveRecord::Base.methods).include?(:with_deleted)
              default_arguments << {:name=>:with_deleted, :type=>GraphQL::BOOLEAN_TYPE, :default=>false, :authorization=>:manage}
            end
            allowed_scope_methods = []
            if scope_methods.count > 0
              scope_methods.each do |s|
                #.select{|m| model.method(m.to_sym).arity == 0}
                allowed_scope_methods << s if (model.public_methods - model.instance_methods - Object.methods - ActiveRecord::Base.methods).include?(s)
              end
              if allowed_scope_methods.count > 0
                scope_enum_type_name = GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(model.name)}Scope_Enum")
                if !GraphqlModelMapper.defined_constant?(scope_enum_type_name)
                  enum_type = GraphQL::EnumType.define do
                    name scope_enum_type_name
                    description "scope enum for #{GraphqlModelMapper.get_type_name(model.name)}"
                    allowed_scope_methods.sort.each do |s|
                      value(s, "")
                    end
                  end
                  GraphqlModelMapper.set_constant scope_enum_type_name, enum_type
                end
                #default_arguments << {:name=>:scope, :type=>GraphqlModelMapper.get_constant(typename), :default=>nil, :authorization=>:manage}

                scope_list_type_name = GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(model.name)}Scope_List")
                if !GraphqlModelMapper.defined_constant?(scope_list_type_name)
                  scope_list_type =  GraphQL::InputObjectType.define do
                    name scope_list_type_name
                    description "scope list for #{GraphqlModelMapper.get_type_name(model.name)}"
                    argument :scope, !GraphqlModelMapper.get_constant(scope_enum_type_name)
                    argument :arguments, GraphQL::STRING_TYPE.to_list_type
                  end
                  GraphqlModelMapper.set_constant scope_list_type_name, scope_list_type
                end
                default_arguments << {:name=>:scopes, :type=>GraphqlModelMapper.get_constant(scope_list_type_name).to_list_type , :default=>nil, :authorization=>:manage}
              end            
            end
            default_arguments
        end
        
        def self.get_resolver(resolver, model, operation)
          if model.public_methods.include?("graphql_#{operation}_resolver".to_sym)
            case operation
              when :create
                resolver = -> (obj, args, ctx) {model.graphql_create_resolver(obj,args,ctx) } if model.public_methods.include?(:graphql_create_resolver)
              when :delete
                resolver = -> (obj, args, ctx) {model.graphql_delete_resolver(obj,args,ctx) } if model.public_methods.include?(:graphql_delete_resolver)
              when :update
                resolver = -> (obj, args, ctx) {model.graphql_update_resolver(obj,args,ctx) } if model.public_methods.include?(:graphql_update_resolver)
            end
          end
          if GraphqlModelMapper.mutation_resolve_wrapper && GraphqlModelMapper.mutation_resolve_wrapper < GraphqlModelMapper::Resolve::ResolveWrapper
            return GraphqlModelMapper.mutation_resolve_wrapper.new(resolver)
          else
            return GraphqlModelMapper::Resolve::ResolveWrapper.new(resolver)
          end
        end
           
    end
end    