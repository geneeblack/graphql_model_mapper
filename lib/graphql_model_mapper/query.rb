module GraphqlModelMapper
    module Query
        def self.graphql_query(name: "",
            description: "",
            resolver: nil,
            arguments: [],
            scope_methods: []
          )
          
            input_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_sub_key: :input_type)
            output_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_sub_key: :output_type)
            self.get_query(name, description, "Query", resolver, arguments, scope_methods, input_type, output_type)
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
=begin            
            default_arguments = default_arguments + [
#              {:name=>:limit, :type=>GraphQL::INT_TYPE, :default=>GraphqlModelMapper.max_page_size}, 
              {:name=>:first, :type=>GraphQL::INT_TYPE, :default=>nil}, 
              {:name=>:last, :type=>GraphQL::INT_TYPE, :default=>nil}, 
              {:name=>:offset, :type=>GraphQL::INT_TYPE, :default=>nil}] if ![:deep, :shallow].include?(GraphqlModelMapper.nesting_strategy)
=end        
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
                default_arguments << {:name=>:scope, :type=>GraphqlModelMapper.get_constant(typename), :default=>nil, :authorization=>:manage}
              end
            end
            default_arguments
        end

        def self.get_query(name, description, operation_name, resolver, arguments, scope_methods, input_type, output_type)
            
            query_type_name = GraphqlModelMapper.get_type_case("#{GraphqlModelMapper.get_type_name(name)}#{operation_name}")
            return GraphqlModelMapper.get_constant(query_type_name) if GraphqlModelMapper.defined_constant?(query_type_name) 
            
            model = name.classify.constantize
        
            default_arguments = arguments ? (arguments.length > 0 ? arguments : self.get_default_select_arguments(model, scope_methods)) : []


=begin
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
=end
=begin
            page_info_type_name = "FlatPageInfo"     
            if GraphqlModelMapper.defined_constant?(page_info_type_name)
              page_info_type = GraphqlModelMapper.get_constant(page_info_type_name)
            else
              page_info_type = GraphQL::ObjectType.define do
                name("FlatPageInfo")
                description("Information about pagination in a query.")
                field :hasNextPage, !types.Boolean, "When paginating forwards, are there more items?", property: :has_next_page
                field :hasPreviousPage, !types.Boolean, "When paginating backwards, are there more items?", property: :has_previous_page
                field :startCursor, types.String, "When paginating backwards, the cursor to continue.", property: :start_cursor
                field :endCursor, types.String, "When paginating forwards, the cursor to continue.", property: :end_cursor
              end
              GraphqlModelMapper.set_constant(page_info_type_name, page_info_type)
            end
=end           



          total_output_type_name = "#{GraphqlModelMapper.get_type_name(name)}QueryPayload"
          if GraphqlModelMapper.defined_constant?(total_output_type_name)
            total_output_type = GraphqlModelMapper.get_constant(total_output_type_name)
          else
            if [:deep, :shallow].include?(GraphqlModelMapper.nesting_strategy)
              connection_type = GraphqlModelMapper::MapperType.get_connection_type(name, output_type)
              total_output_type = GraphQL::ObjectType.define do
                name total_output_type_name
                connection :items, -> {connection_type}, max_page_size: GraphqlModelMapper.max_page_size do 
                      resolve -> (obj, args, ctx) {
                          limit = GraphqlModelMapper.max_page_size
                          raise GraphQL::ExecutionError.new("you have exceeded the maximum requested page size #{limit}") if args[:first].to_i > limit || args[:last].to_i > limit

                          obj
                      }
                  end
              end
            else
                total_output_type = GraphqlModelMapper::MapperType.get_list_type(name, output_type)
            end
            GraphqlModelMapper.set_constant(total_output_type_name, total_output_type)              
          end

        
              
            ret_type = GraphQL::Field.define do
                name query_type_name
                type total_output_type
                default_arguments.each do |k|
                  argument k[:name].to_sym, k[:type], k[:description], default_value: k[:default] do                  
                    if k[:authorization] && GraphqlModelMapper.use_authorize
                      authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
                      model_name name
                      access_type k[:authorization] 
                    end       
                  end
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