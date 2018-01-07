module GraphqlModelMapper
    module Query
        def self.graphql_query(name: "",
            description: "",
            resolver: nil,
            arguments: [],
            scope_methods: [],
            root_query: false
          )
          resolver = resolver || -> (obj, args, ctx) {              
            items = GraphqlModelMapper::Resolve.query_resolver(obj, args, ctx, name)
          }
          
            #input_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_sub_key: :input_type)
            output_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_sub_key: :output_type)
            self.get_query(name, description, "Query", resolver, arguments, scope_methods, output_type)
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
            if (model.public_methods - model.instance_methods - Object.methods - ActiveRecord::Base.methods).include?(:with_deleted)
              default_arguments << {:name=>:with_deleted, :type=>GraphQL::BOOLEAN_TYPE, :default=>false, :authorization=>:manage}
            end
            allowed_scope_methods = []
            if scope_methods.count > 0
              scope_methods.each do |s|
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

        def self.get_query(name, description, operation_name, resolver, arguments, scope_methods, output_type)

            
          query_type_name = GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(name)}#{operation_name}")
          return GraphqlModelMapper.get_constant(query_type_name) if GraphqlModelMapper.defined_constant?(query_type_name) 
          
          model = name.classify.constantize
      
          default_arguments = arguments ? (arguments.length > 0 ? arguments : self.get_default_select_arguments(model, scope_methods)) : []



          total_output_type_name = "#{GraphqlModelMapper.get_type_name(name)}QueryPayload"
          if GraphqlModelMapper.defined_constant?(total_output_type_name)
            total_output_type = GraphqlModelMapper.get_constant(total_output_type_name)
          else
            if [:deep, :shallow].include?(GraphqlModelMapper.nesting_strategy)
              total_output_type = GraphQL::ObjectType.define do
                name total_output_type_name
                connection :items, -> { GraphqlModelMapper::MapperType.get_connection_type(name, output_type, false) }, max_page_size: GraphqlModelMapper.max_page_size do 
                      resolve -> (obj, args, ctx) {
                        limit = GraphqlModelMapper.max_page_size
                        raise GraphQL::ExecutionError.new("you have requested more items than the maximum page size #{limit}") if obj.length > limit && (args[:first].to_i > limit || args[:last].to_i > limit)
                        obj
                      }
                  end
              end
            else
                total_output_type = -> { GraphqlModelMapper::MapperType.get_list_type(name, output_type, false) }
            end
            GraphqlModelMapper.set_constant(total_output_type_name, total_output_type)              
          end

        
              
          ret_type = GraphQL::Field.define do
              name query_type_name
              type total_output_type
              default_arguments.each do |k|
                argument k[:name].to_sym, k[:type], k[:description], default_value: k[:default]
              end
              resolve GraphqlModelMapper::Query.get_resolver(resolver, model)
          end
          GraphqlModelMapper.set_constant(query_type_name, ret_type)
          GraphqlModelMapper.get_constant(query_type_name)
      end


      def self.get_resolver(resolver, model)
        
        resolver = -> (obj,args,ctx){ model.graphql_query_resolver(obj, args, ctx) } if model.public_methods.include?(:graphql_query_resolver)

        if GraphqlModelMapper.query_resolve_wrapper && GraphqlModelMapper.query_resolve_wrapper < GraphqlModelMapper::Resolve::ResolveWrapper
          return GraphqlModelMapper.query_resolve_wrapper.new(resolver)
        else
          return GraphqlModelMapper::Resolve::ResolveWrapper.new(resolver)
        end
      end
    end
end    