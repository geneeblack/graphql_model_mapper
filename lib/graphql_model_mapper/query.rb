module GraphqlModelMapper
    module Query
        def self.graphql_query(name: "",
            description: "",
            resolver: -> (obj, args, ctx) {              
              items = GraphqlModelMapper::Resolve.query_resolver(obj, args, ctx, name)
              {
                items: items,
                total: items.length
              }

            },
            arguments: [],
            scope_methods: []
          )
          
            input_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_key: :query, type_sub_key: :input_type)
            output_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_key: :query, type_sub_key: :output_type)
            self.get_query(name, description, "Query", resolver, arguments, scope_methods, input_type, output_type)
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

        def self.get_query(name, description, operation_name, resolver, arguments, scope_methods, input_type, output_type)
            
            query_type_name = GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(name)}#{operation_name}")
            return GraphqlModelMapper.get_constant(query_type_name) if GraphqlModelMapper.defined_constant?(query_type_name) 
            
            model = name.classify.constantize
        
            default_arguments = self.get_default_select_arguments(model, scope_methods)
            select_input_type_name = "#{GraphqlModelMapper.get_type_case(GraphqlModelMapper.get_type_name(name))}QueryInput"     
            if GraphqlModelMapper.defined_constant?(select_input_type_name)
              select_input_type = GraphqlModelMapper.get_constant(select_input_type_name)
            else
              select_input_type = GraphQL::InputObjectType.define do
                name select_input_type_name
                default_arguments.each do |k|
                  argument k[:name].to_sym, k[:type], k[:description], default_value: k[:default] 
                end
              end
              GraphqlModelMapper.set_constant(select_input_type_name, select_input_type)
            end
        
            total_output_type_name = "#{GraphqlModelMapper.get_type_name(name)}QueryPayload"
            if GraphqlModelMapper.defined_constant?(total_output_type_name)
              total_output_type = GraphqlModelMapper.get_constant(total_output_type_name)
            else
              total_output_type = GraphQL::ObjectType.define do
                name total_output_type_name
                if [:deep, :shallow].include?(GraphqlModelMapper.nesting_strategy)
                  connection :items, -> {output_type.connection_type}, hash_key: :items
                else
                  field :items, -> {output_type.to_list_type}, hash_key: :items
                end
                field :total, -> {GraphQL::INT_TYPE}, hash_key: :total
              end
              GraphqlModelMapper.set_constant(total_output_type_name, total_output_type)
            end
        
              
            ret_type = GraphQL::Field.define do
                name query_type_name
                type total_output_type
                #argument :select, -> {!select_input_type}
                default_arguments.each do |k|
                  argument k[:name].to_sym, k[:type], k[:description], default_value: k[:default] 
                end
        
                resolve resolver 
              end
            GraphqlModelMapper.set_constant(query_type_name, ret_type)
            GraphqlModelMapper.get_constant(query_type_name)
        end
    end
end    