module GraphqlModelMapper
    module MapperType
        delegate :url_helpers, to: 'Rails.application.routes'

        def self.graphql_types(
            name: self.name,
            input_type: {},
            output_type: {}
            )
            return GraphqlModelMapper::CustomType.const_get("#{name.upcase}_GRAPHQL_DEFAULT_TYPES") if GraphqlModelMapper::CustomType.const_defined?("#{name.upcase}_GRAPHQL_DEFAULT_TYPES") 
            graphql_type = {}
            graphql_type[:input_type] = input_type
            graphql_type[:input_type][:type_sub_key] = :input_type
            graphql_type[:output_type] = output_type
            graphql_type[:output_type][:type_sub_key] = :output_type
            merged_graphql_type = self.graphql_default_types.deep_merge(graphql_type)
            GraphqlModelMapper::CustomType.const_set("#{name.upcase}_GRAPHQL_DEFAULT_TYPES", merged_graphql_type)

            merged_graphql_type
        end


        def self.graph_object(name)
            if GraphqlModelMapper.implementations.map(&:to_s).include?(name.classify)
                self.get_ar_object_with_params(name)
            else
                name.classify.constantize
            end
        end

        def self.get_ar_object_with_params(name, type_sub_key: :output_type)
            self.get_ar_object(name, self.get_type_params(name, type_sub_key: type_sub_key))
        end

        
        def self.get_ar_object(name, 
            required_attributes: [], 
            excluded_attributes: [], 
            allowed_attributes: [],
            foreign_keys: true, 
            primary_keys: true, 
            validation_keys: false, 
            association_macro: nil, 
            source_nulls: true,
            type_sub_key: nil)
        
            
            #typesuffix = method(__method__).parameters.map { |arg| eval arg[1].to_s }.hash.abs.to_i.to_s
            #typesuffix = "#{type_key.to_s.classify}#{GraphqlModelMapper.underscore(type_sub_key.to_s)}".camelize
            typesuffix = "#{GraphqlModelMapper.underscore(type_sub_key.to_s).sub("_Type", "")}".camelize
            #typesuffix = "#{type_sub_key == :input_type ? '_i' : '_o'}"
            typename = "#{GraphqlModelMapper.get_type_name(name)}#{typesuffix}"
            
            return GraphqlModelMapper.get_constant(typename) if GraphqlModelMapper.defined_constant?(typename)
        
            model = name.classify.constantize
        
            required_attributes = required_attributes.map(&:to_sym) | (validation_keys ? self.model_validation_keys(name) : [])
            
            columns = model.columns_hash
        
            # figure out which association fields we are exposing
            association_includes =  (model.reflect_on_all_associations(association_macro).map(&:name)).map(&:to_sym) - excluded_attributes 
        
            # find all relations for this model, skip ones where the association klass is invalid, be cognizant of include/exclude arrays similar to dbfields
            associations = model.reflect_on_all_associations(association_macro).select{|t| begin t.klass rescue next end}.select{|t| association_includes.include?(t.name.to_sym) }
            # now include polymorphic relations whose association klass is invalid, but is correct 
            associations = associations + model.reflect_on_all_associations(association_macro).select{|t| t.options[:polymorphic]}.select{|t| association_includes.include?(t.name.to_sym) } 
            # never show foreign keys for defined associations
            db_fields_never = foreign_keys ? [] : ( model.reflect_on_all_associations.map(&:association_foreign_key) + model.reflect_on_all_associations.map(&:options).select{|v| v.key?(:foreign_key) }.map {|x| x[:foreign_key]} ).uniq.map(&:to_sym)
                
            # figure out which database fields we are exposing
            allowed_attributes = allowed_attributes.count > 0 ? allowed_attributes.map(&:to_sym) : associations.map(&:name) + columns.keys.map(&:to_sym)
            allowed_associations = (associations.map(&:name) - excluded_attributes - db_fields_never) & allowed_attributes
            db_fields = (columns.keys.map(&:to_sym) - excluded_attributes - db_fields_never) & allowed_attributes
            associations = associations.select{|m| allowed_associations.include?(m.name)}
            enums = (Rails.version.split(".").first.to_i >= 4 && Rails.version.split(".").second.to_i >= 1) || (Rails.version.split(".").first.to_i >= 5) ? model.defined_enums.keys : [] 
            enum_values = (Rails.version.split(".").first.to_i >= 4 && Rails.version.split(".").second.to_i >= 1) || (Rails.version.split(".").first.to_i >= 5) ? model.defined_enums : [] 
            

            begin 
                property_enum_type = self.get_property_enum_type(name, associations, db_fields, columns)
                model_filter = GraphQL::InputObjectType.define do
                    name typename
                
                    argument :column, property_enum_type
                    argument :direction, !GraphqlModelMapper::SortOrderEnum
                end
                
                
                ret_type = model_filter.to_list_type
            end if type_sub_key == :order_type

            ret_type = GraphQL::InputObjectType.define do
                #ensure type name is unique  so it does not collide with known types
                name typename
                description "an input interface for the #{name} ActiveRecord model"
                # create GraphQL fields for each association
                arguments = []
                associations.sort_by(&:name).each do |reflection|
                    begin
                        klass = reflection.klass if !reflection.options[:polymorphic]
                        next if !(klass.public_methods.include?(:graphql_delete) || klass.public_methods.include?(:graphql_create) || klass.public_methods.include?(:graphql_update))
                    rescue
                        GraphqlModelMapper.logger.info("invalid relation #{reflection.name} specified on the #{name} model, the relation class does not exist")
                        next # most likely an invalid association without a class name, skip if other errors are encountered
                    end                    
                    if reflection.macro != :has_many
                        if reflection.options[:polymorphic] #not currently supported as an input type
                            #if GraphqlModelMapper.scan_for_polymorphic_associations
                            #    argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_polymorphic_type(reflection, name, type_sub_key: type_sub_key)}    
                            #end
                        else

                            arg = GraphQL::Argument.define do 
                                name reflection.name.to_sym
                                type -> {GraphqlModelMapper::MapperType.get_ar_object(klass.name, type_sub_key: type_sub_key)}
                                if GraphqlModelMapper.use_authorize
                                    authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true  }
                                    model_name klass.name
                                    access_type :read
                                end
                            end
                            arguments << arg
        
                            #argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object(klass.name, type_sub_key: type_sub_key)} do
                            #    if GraphqlModelMapper.use_authorize
                            #        authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true  }
                            #        model_name klass.name
                            #        access_type :read
                            #    end
                            #end 
                        end 
                    end                
                end
        
                db_fields.sort.each do |f|
                    arg = GraphQL::Argument.new
                    arg.name = f.to_sym
                    arg.type = -> {GraphqlModelMapper::SortOrderEnum} #{GraphqlModelMapper::StringCompare}
                    arguments << arg
                    #argument f.to_sym, -> {GraphqlModelMapper::SortOrderEnum} #{GraphqlModelMapper::StringCompare}
                end

                arguments.sort_by(&:name).each do |a|
                    argument a.name, a.type 
                end
            end.to_list_type  if type_sub_key == :order_type_full


            begin 

                property_enum_type = self.get_property_enum_type(name, associations, db_fields, columns)
                model_filter = GraphQL::InputObjectType.define do
                    name typename
                
                    argument :OR, -> { model_filter }
                    argument :column, property_enum_type
                    argument :compare, !GraphqlModelMapper::StringCompareEnum
                    argument :value, types.String #types.String || types.Number || types.GeometryObject || types.FLOAT_TYPE || types.BOOLEAN_TYPE
                end


                ret_type = model_filter.to_list_type
            end if type_sub_key == :search_type


            ret_type = GraphQL::InputObjectType.define do
                #ensure type name is unique  so it does not collide with known types
                name typename
                description "an input interface for the #{name} ActiveRecord model"
                # create GraphQL fields for each association
                if associations.count == 0 
                    argument "include".to_sym, GraphQL::BOOLEAN_TYPE
                end
                associations.sort_by(&:name).each do |reflection|
                    begin
                        klass = reflection.klass if !reflection.options[:polymorphic]
                        next if !(klass.public_methods.include?(:graphql_delete) || klass.public_methods.include?(:graphql_create) || klass.public_methods.include?(:graphql_update))
                    rescue
                        GraphqlModelMapper.logger.info("invalid relation #{reflection.name} specified on the #{name} model, the relation class does not exist")
                        next # most likely an invalid association without a class name, skip if other errors are encountered
                    end                    
                    if reflection.macro == :has_many
                        argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object(klass.name, type_sub_key: type_sub_key)} do
                            if GraphqlModelMapper.use_authorize
                                authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true }
                                model_name klass.name
                                access_type :read
                            end
                        end   
                    else
                        if reflection.options[:polymorphic] #not currently supported as an input type
                            #if GraphqlModelMapper.scan_for_polymorphic_associations
                            #    argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_polymorphic_type(reflection, name, type_sub_key: type_sub_key)}    
                            #end
                        else
                            argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object(klass.name, type_sub_key: type_sub_key)} do
                                if GraphqlModelMapper.use_authorize
                                    authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true  }
                                    model_name klass.name
                                    access_type :read
                                end
                            end 
                        end 
                    end                
                end        
            end  if type_sub_key == :includes_type
                            

            ret_type = GraphQL::InputObjectType.define do
                #ensure type name is unique  so it does not collide with known types
                name typename
                description "an input interface for the #{name} ActiveRecord model"
                # create GraphQL fields for each association
                associations.sort_by(&:name).each do |reflection|
                    begin
                        klass = reflection.klass if !reflection.options[:polymorphic]
                        next if !(klass.public_methods.include?(:graphql_delete) || klass.public_methods.include?(:graphql_create) || klass.public_methods.include?(:graphql_update))
                    rescue
                        GraphqlModelMapper.logger.info("invalid relation #{reflection.name} specified on the #{name} model, the relation class does not exist")
                        next # most likely an invalid association without a class name, skip if other errors are encountered
                    end                    
                    if reflection.macro == :has_many
                        argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object(klass.name, type_sub_key: type_sub_key)} do
                            if GraphqlModelMapper.use_authorize
                                authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true }
                                model_name klass.name
                                access_type :read
                            end
                        end   
                    else
                        if reflection.options[:polymorphic] #not currently supported as an input type
                            #if GraphqlModelMapper.scan_for_polymorphic_associations
                            #    argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_polymorphic_type(reflection, name, type_sub_key: type_sub_key)}    
                            #end
                        else
                            argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object(klass.name, type_sub_key: type_sub_key)} do
                                if GraphqlModelMapper.use_authorize
                                    authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true  }
                                    model_name klass.name
                                    access_type :read
                                end
                            end 
                        end 
                    end                
                end
        
                db_fields.sort.each do |f|
                    argument f.to_sym, -> {GraphqlModelMapper::MapperType.convert_compare_type(columns[f.to_s].type, columns[f.to_s].sql_type, true).to_list_type} #{GraphqlModelMapper::StringCompare}
                end
            end  if type_sub_key == :search_type_full
                            

            ret_type = GraphQL::InputObjectType.define do
                #ensure type name is unique  so it does not collide with known types
                name typename
                description "an input interface for the #{name} ActiveRecord model"
                # create GraphQL fields for each association
                associations.sort_by(&:name).each do |reflection|
                    begin
                        klass = reflection.klass if !reflection.options[:polymorphic]
                        next if !(klass.public_methods.include?(:graphql_delete) || klass.public_methods.include?(:graphql_create) || klass.public_methods.include?(:graphql_update))
                    rescue
                        GraphqlModelMapper.logger.info("invalid relation #{reflection.name} specified on the #{name} model, the relation class does not exist")
                        next # most likely an invalid association without a class name, skip if other errors are encountered
                    end                    
                    if reflection.macro == :has_many
                        argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_sub_key: type_sub_key).to_list_type} do
                            if GraphqlModelMapper.use_authorize
                                authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true  }
                                model_name klass.name
                                access_type :read
                            end
                        end   
                    else
                        if reflection.options[:polymorphic] #not currently supported as an input type
                            #if GraphqlModelMapper.scan_for_polymorphic_associations
                            #    argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_polymorphic_type(reflection, name, type_sub_key: type_sub_key)}    
                            #end
                        else
                            argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_sub_key: type_sub_key)} do
                                if GraphqlModelMapper.use_authorize
                                    authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true  }
                                    model_name klass.name
                                    access_type :read
                                end
                            end 
                        end
                    end                
                end
        
                # create GraphQL fields for each exposed database field
                #if primary keys were requested
                db_fields.select{|s| (primary_keys && s.to_sym == :id)}.each do |f|
                    argument "item_id".to_sym, -> {GraphqlModelMapper::MapperType.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, (source_nulls ? columns[f.to_s].null : true))}
                end
                argument :id, GraphQL::ID_TYPE       
                # force required_attributes to be non-null
                db_fields.select{|s| required_attributes.include?(s)}.each do |f|
                    argument f.to_sym, -> {GraphqlModelMapper::MapperType.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, false)}
                end       
                #get the rest of the fields that are not primary keys or required fields
                db_fields.reject{|s| (s.to_sym == :id) || required_attributes.include?(s)}.sort.each do |f|
                    custom_type_name = "#{name.classify}#{f.to_s.classify}AttributeInput"
                    if GraphqlModelMapper::CustomType.const_defined?(custom_type_name)
                        argument f.to_sym, GraphqlModelMapper::CustomType.const_get(custom_type_name)
                    else
                        if enums.include?(f.to_s)
                            argument f.to_sym, -> {GraphqlModelMapper::MapperType.get_enum_object(name, enum_values[f.to_s], f.to_s)}
                        else
                            argument f.to_sym, -> {GraphqlModelMapper::MapperType.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, (source_nulls ? columns[f.to_s].null : true))}
                        end
                    end
                end
            end if type_sub_key == :input_type
        
            ret_type = GraphQL::ObjectType.define do
                #ensure type name is unique  so it does not collide with known types
                name typename
                model_name name
                authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true  }
                access_type :read.to_s
 
                description "an output interface for the #{name} ActiveRecord model"
                # create GraphQL fields for each association
                associations.sort_by(&:name).each do |reflection|
                    begin
                        klass = reflection.klass if !reflection.options[:polymorphic]
                        next if !reflection.options[:polymorphic] && klass && !klass.public_methods.include?(:graphql_query)
                    rescue
                        GraphqlModelMapper.logger.info("invalid relation #{reflection.name} specified on the #{name} model, the relation class does not exist")
                        next # most likely an invalid association without a class name, skip it
                    end                    
                    if reflection.macro == :has_many
                        if [:deep].include?(GraphqlModelMapper.nesting_strategy)
                            #connection reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_connection_type(klass.name, GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_sub_key: type_sub_key))}, property: reflection.name.to_sym, max_page_size: GraphqlModelMapper.max_page_size do
                            field reflection.name.to_sym, GraphqlModelMapper::MapperType.get_query_type(klass.name, GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_sub_key: type_sub_key)) do
                                if GraphqlModelMapper.use_authorize
                                    authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true  }
                                    model_name klass.name
                                    access_type :read.to_s
                                end
                            end 
                        else
                            #field reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_list_type(klass.name, GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_sub_key: type_sub_key))}, property: reflection.name.to_sym do
                            field reflection.name.to_sym, GraphqlModelMapper::MapperType.get_query_type(klass.name, GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_sub_key: type_sub_key)) do
                                    if GraphqlModelMapper.use_authorize
                                    authorized ->(ctx, model_name, access_type) {GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true  }
                                    model_name klass.name
                                    access_type :read.to_s
                                end
                            end    
                        end
                    else
                        if reflection.options[:polymorphic]
                            # if a union type is defined in custom types use it, otherwise generate a union type from the association definition (requires a table scan)
                            custom_type_name = "#{name.classify}#{reflection.name.to_s.classify}Union"
                            if GraphqlModelMapper::CustomType.const_defined?(custom_type_name)
                                field reflection.name.to_sym, -> {GraphqlModelMapper::CustomType.const_get(custom_type_name)} do
                                end 
                            elsif GraphqlModelMapper.scan_for_polymorphic_associations
                                field reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_polymorphic_type(reflection, name)}, property: reflection.name.to_sym do
                                end    
                            end 
                        else
                            field reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_sub_key: type_sub_key)}, property: reflection.name.to_sym do
                            if GraphqlModelMapper.use_authorize
                                    authorized ->(ctx, model_name, access_type) {  
                                        GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true  
                                    }
                                    model_name klass.name
                                    access_type :read.to_s
                                end
                            end   
                        end
                    end
                end                        
                # create GraphQL fields for each exposed database field
                # get primary keys if requested
                implements GraphQL::Relay::Node.interface
                global_id_field :id    
                db_fields.select{|s| (primary_keys && s.to_sym == :id)}.each do |f|
                    field "item_id".to_sym, -> {GraphqlModelMapper::MapperType.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, (source_nulls ? columns[f.to_s].null : true))}, property: :id do
                    resolve -> (obj, args, ctx) {
                        obj[:id]
                    }
                    end
                end
                # force required attributes to be non-null
                db_fields.select{|s| required_attributes.include?(s)}.sort.each do |f|
                    field f.to_sym, -> {GraphqlModelMapper::MapperType.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, false)}, property: f.to_sym
                end       
                # get the remaining fields and apply custom type if defined
                db_fields.reject{|s| (s.to_sym == :id) || required_attributes.include?(s)}.sort.each do |f|
                    custom_type_name = "#{name.classify}#{f.to_s.classify}AttributeOutput"
                    if GraphqlModelMapper::CustomType.const_defined?(custom_type_name)
                        field f.to_sym, GraphqlModelMapper::CustomType.const_get(custom_type_name)
                    else
                        if enums.include?(f.to_s)
                            field f.to_sym, -> {GraphqlModelMapper::MapperType.get_enum_object(name, enum_values[f.to_s], f.to_s)}, property: f.to_sym
                        else
                            field f.to_sym, -> {GraphqlModelMapper::MapperType.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, (source_nulls ? columns[f.to_s].null : true))}, property: f.to_sym
                        end
                    end
                end
=begin
                field :model_url, types.String do
                    description 'web show url'
                    resolve -> (obj, args, ctx) {
                        [GraphqlModelMapper::Resolve.get_node_parent(ctx.parent.irep_node).name.singularize, obj.id].join("-")
                    }
                end
                field :node_reference, types.String do
                    description 'a graphql query for this record'
                    resolve -> (obj, args, ctx) {
                        #binding.pry
                        [ GraphqlModelMapper::Resolve.get_node_parent(ctx.parent.irep_node).name.singularize.downcase, obj.id].join("-")
                    }
                end
=end
            end if type_sub_key == :output_type
            GraphqlModelMapper.set_constant(typename, ret_type) if !GraphqlModelMapper.defined_constant?(typename)
            ret_type
        end
    

        def self.get_polymorphic_type(reflection, model_name)
            type_name = "#{model_name}#{reflection.name.to_s.classify}Union"

            return GraphqlModelMapper.get_constant(type_name) if GraphqlModelMapper.defined_constant?(type_name)

            model = model_name.classify.constantize
            has_with_deleted = model.public_methods.include?(:with_deleted)
            parent_name = "#{reflection.name}_type"
            parent_classes = has_with_deleted ? model.with_deleted.select("distinct #{parent_name}").map{|m| m.send("#{parent_name}".to_sym)} :  model.select("distinct #{parent_name}").map{|m| m.send("#{parent_name}".to_sym)}
            types = []
            parent_classes.each do |p|                
                types << self.get_ar_object_with_params(p, type_sub_key: :output_type) if p.classify.constantize.public_methods.include?(:graphql_query)
            end
            if GraphqlModelMapper.use_authorize || types.length == 0
                types << GraphqlModelMapper::UNAUTHORIZED
            end
            ret_type = GraphQL::UnionType.define do
                name type_name
                description "UnionType for polymorphic association #{reflection.name} on #{model_name}"
                possible_types types
                resolve_type ->(obj, ctx) {
                    if GraphqlModelMapper.use_authorize
                        if GraphqlModelMapper.authorized?(ctx, obj.class.name)
                          return GraphqlModelMapper::MapperType.graph_object(obj.class.name)
                        else
                          return GraphqlModelMapper::UNAUTHORIZED
                        end
                      else
                        GraphqlModelMapper::MapperType.graph_object(obj.class.name)
                      end
                }
                if GraphqlModelMapper.use_authorize
                    authorized ->(ctx, model_name, access_type) {  GraphqlModelMapper.use_graphql_object_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true  }
                    model_name model_name
                    access_type :read
                end
            end
            GraphqlModelMapper.set_constant(type_name, ret_type)
            GraphqlModelMapper.get_constant(type_name)
        end

        def self.get_type_params(name, type_sub_key: :output_type)
            model = name.classify.constantize
            if model.public_methods.include?(:graphql_types)
                params = model.graphql_types
            else
                params = self.graphql_default_types
            end
            if !type_sub_key.nil?
                if params.keys.include?(type_sub_key.to_sym)
                    params = params[type_sub_key.to_sym]
                else
                    params = nil
                end
            else
                params = nil
            end
            params[:type_sub_key] = type_sub_key
            params 
        end
    

        def self.get_query_type(model_name, output_type)
            model = model_name.classify.constantize
            model.graphql_query
            #GraphqlModelMapper::Query.get_query(model_name, "description", "Query", nil, [], [], output_type)
        end

        def self.get_connection_type(model_name, output_type, root=false)
            root = root && GraphqlModelMapper.encrypted_items
            connection_type_name = "#{GraphqlModelMapper.get_type_case(GraphqlModelMapper.get_type_name(model_name))}#{root ? "Root" : ""}Connection"
            if GraphqlModelMapper.defined_constant?(connection_type_name)
                connection_type = GraphqlModelMapper.get_constant(connection_type_name)
            else
                connection_type = output_type.define_connection do
                    name connection_type_name
                    if root
                        field :ep, hash_key: :ep do
                            type GraphQL::STRING_TYPE
                            resolve ->(obj, args, ctx) {
                                GraphqlModelMapper::Encryption.encode(GraphQL::Schema::UniqueWithinType.encode(model_name, ctx.parent.parent.irep_node.arguments.to_h.with_indifferent_access.to_json)).to_s

                                ctx.parent.parent.irep_node.arguments.to_h.with_indifferent_access.to_json
                            }
                        end
                        field :qp, hash_key: :qp do
                            type GraphQL::STRING_TYPE
                            resolve ->(obj, args, ctx) {
                                GraphqlModelMapper::Encryption.encode(ctx.query.query_string.sub("ep", "").sub("qp","")).to_s
                                ctx.query.query_string.sub("ep", "").sub("qp","")                            
                            }
                        end
                    end
                    field :totalCount, hash_key: :total do
                        type GraphQL::INT_TYPE
                        resolve ->(obj, args, ctx) {
                            obj.nodes.limit(nil).count
                        }
                    end
                end
                GraphqlModelMapper.set_constant(connection_type_name, connection_type)
            end
            return GraphqlModelMapper.get_constant(connection_type_name)
        end

        def self.get_list_type(model_name, output_type, root=false)
            root = root && GraphqlModelMapper.encrypted_items
            list_type_name = "#{GraphqlModelMapper.get_type_case(GraphqlModelMapper.get_type_name(model_name))}#{root ? "Root" : ""}List"     
            if GraphqlModelMapper.defined_constant?(list_type_name)
                list_type = GraphqlModelMapper.get_constant(list_type_name)
            else
                developer_type_name = "DevelopmentInfo"
                if GraphqlModelMapper.defined_constant?(developer_type_name)
                    developer_type = GraphqlModelMapper.get_constant(developer_type_name)
                else
                    developer_type = GraphQL::ObjectType.define do
                        name developer_type_name
                        field :node_arguments, GraphQL::STRING_TYPE, hash_key: :node_arguments do
                            resolve ->(obj, args, ctx) {
                                GraphqlModelMapper::Resolve.resolve_node_arguments(obj, args, ctx)
                            }
                        end
                        field :parent_arguments, GraphQL::STRING_TYPE,  hash_key: :parent_arguments do
                            resolve ->(obj, args, ctx) {
                                GraphqlModelMapper::Resolve.resolve_parent_arguments(obj, args, ctx)
                            }
                        end
                        field :node_query, GraphQL::STRING_TYPE, hash_key: :node_query do
                            resolve ->(obj, args, ctx) {
                                GraphqlModelMapper::Resolve.resolve_node_query(obj, args, ctx)
                            }
                        end
    
                    end
                    GraphqlModelMapper.set_constant(developer_type_name, developer_type)
                end


                page_info_type_name = "PagingInfo"
                if GraphqlModelMapper.defined_constant?(page_info_type_name) 
                    page_info_type = GraphqlModelMapper.get_constant(page_info_type_name)
                else
                    page_info_type = GraphQL::ObjectType.define do
                        name page_info_type_name
                        field :totalItems, -> {GraphQL::INT_TYPE}, hash_key: :total do 
                            resolve->(obj,args, ctx){
                                ctx[:total_count] || obj.count
                            }
                        end
                        field :hasNextPage, GraphQL::BOOLEAN_TYPE do 
                            resolve->(obj,args, ctx){
                                ctx[:has_next_page]
                            }
                        end
                        field :hasPriorPage, GraphQL::BOOLEAN_TYPE do 
                            resolve->(obj,args, ctx){
                                ctx[:has_prior_page]
                            }
                        end
                        field :currentPage, GraphQL::INT_TYPE do 
                            resolve->(obj,args, ctx){
                                ctx[:current_page]
                            }
                        end
                        field :totalPages, GraphQL::INT_TYPE do 
                            resolve->(obj,args, ctx){
                                ctx[:page_count]
                            }
                        end
                        field :itemsPerPage, GraphQL::INT_TYPE do 
                            resolve->(obj,args, ctx){
                                ctx[:per_page]
                            }
                        end
                        field :nextPageUrl, GraphQL::INT_TYPE do 
                            resolve->(obj,args, ctx){
                                ctx[:per_page]
                            }
                        end
                        field :previousPageUrl, GraphQL::INT_TYPE do 
                            resolve->(obj,args, ctx){
                                ctx[:per_page]
                            }
                        end
                        field :sourceUrl, GraphQL::INT_TYPE do 
                            resolve->(obj,args, ctx){
                                ctx[:per_page]
                            }
                        end

                    end
                    GraphqlModelMapper.set_constant(page_info_type_name, page_info_type)
                end
                list_type = GraphQL::ObjectType.define do
                    name(list_type_name)
                    
                    field :items, -> {output_type.to_list_type}, hash_key: :items do
#                        argument :perPage, GraphQL::INT_TYPE
#                        argument :page, GraphQL::INT_TYPE
                        resolve -> (obj,args,ctx){ 
                            ctx[:items] || GraphqlModelMapper::MapperType.resolve_list(obj,args,ctx) 
                        }
                    end
                    field :paging, -> { GraphqlModelMapper.get_constant(page_info_type_name) }, hash_key: :paging do 
                        argument :perPage, GraphQL::INT_TYPE
                        argument :page, GraphQL::INT_TYPE
                        resolve -> (obj,args,ctx){ 
                            ctx[:total_count] = obj.count
                            ctx[:per_page] = args[:perPage] || GraphqlModelMapper.max_page_size
                            ctx[:per_page] = [ GraphqlModelMapper.max_page_size, ctx[:per_page] ].min
                            ctx[:current_page] = args[:page] ? [args[:page],1].max : 1
                            ctx[:page_count] = (ctx[:total_count]/ctx[:per_page]).ceil
                            ctx[:current_page] = [ctx[:page_count], ctx[:current_page] ].min
                            ctx[:has_prior_page] = ctx[:current_page] > 1
                            ctx[:has_next_page] = ctx[:current_page] < ctx[:page_count]

                            ctx[:items] = GraphqlModelMapper::MapperType.resolve_list(obj,args,ctx)                            
                            ctx[:items]                        }
                    end

                    field :development, -> { GraphqlModelMapper.get_constant(developer_type_name) }, hash_key: :development do
                        resolve -> (obj, args, ctx) {
                            obj
                        }
                    end
                end
                GraphqlModelMapper.set_constant(list_type_name, list_type)
            end
            GraphqlModelMapper.get_constant(list_type_name)
        end


        def self.resolve_list(obj, args, ctx)
            first_rec = nil
            last_rec = nil
            limit = GraphqlModelMapper.max_page_size.to_i
            
            if args[:perPage]
                per_page = [args[:perPage].to_i, 1].max
                limit = [per_page,limit].min
            end
            if args[:page]
                ##binding.pry
                page = [ctx[:page_count], args[:page]].min
                page = [page, 1].max
                obj = obj.offset((page-1)*limit)
            end
            obj = obj.limit(limit)
            obj
        end

        def self.graphql_default_types(
                input_type: {
                    required_attributes: [], 
                    excluded_attributes: [], 
                    allowed_attributes: [], 
                    foreign_keys: true, 
                    primary_keys: true, 
                    validation_keys: false, 
                    association_macro: nil, 
                    source_nulls: false
                },
                output_type: {
                    required_attributes: [], 
                    excluded_attributes: [], 
                    allowed_attributes: [], 
                    foreign_keys: true, 
                    primary_keys: true, 
                    validation_keys: false, 
                    association_macro: nil, 
                    source_nulls: false
                }
            )
            return GraphqlModelMapper::CustomType.const_get("GRAPHQL_DEFAULT_TYPES") if GraphqlModelMapper::CustomType.const_defined?("GRAPHQL_DEFAULT_TYPES") 
                
            graphql_type = {}
            graphql_type[:input_type] = input_type
            graphql_type[:output_type] = output_type
            
            GraphqlModelMapper::CustomType.const_set("GRAPHQL_DEFAULT_TYPES", graphql_type)
            graphql_type
        end
    
        def self.model_validation_keys(name)
            model = name.classify.constantize
            validation_attributes = model.validators.select{|m| m.is_a?(ActiveModel::Validations::PresenceValidator) && !m.options[:if]}.map(&:attributes).flatten
            model.reflect_on_all_associations.select{|p| validation_attributes.include?(p.name) }.map(&:foreign_key).map(&:to_sym)  | validation_attributes & model.columns_hash.keys.map(&:to_sym)
        end

        def self.get_enum_object(model_name, enum, enum_name)
            enum_values = enum.keys
            type_name = "#{model_name.classify}#{enum_name.classify}Enum"
            return GraphqlModelMapper.get_constant(type_name) if GraphqlModelMapper.defined_constant?(type_name)
            ret_type = GraphQL::EnumType.define do
                name type_name
                description "generated GraphQL enum for ActiveRecord enum #{enum_name} on model #{model_name}"
                enum_values.each do |v|
                    value(v.classify, "", value: v)
                end
            end
            GraphqlModelMapper.set_constant(type_name, ret_type)
            GraphqlModelMapper.get_constant(type_name)
        end


        def self.convert_compare_type db_type, db_sql_type="", nullable=true
            # because we are outside of a GraphQL define block we cannot use the types helper
            # we must refer directly to the built-in GraphQL scalar types
            case db_type
            when :integer
                nullable ? GraphqlModelMapper::IntCompare : !GraphqlModelMapper::IntCompare
            when :decimal, :float
                nullable ? GraphqlModelMapper::FloatCompare : !GraphqlModelMapper::FloatCompare
            when :boolean
                nullable ? GraphqlModelMapper::BooleanCompare : !GraphqlModelMapper::BooleanCompare
            when :date, :datetime
                nullable ? GraphqlModelMapper::DateCompare : !GraphqlModelMapper::DateCompare
            else
                case db_sql_type.to_sym #these are strings not symbols
                when :geometry, :multipolygon, :polygon
                    case db_type
                        when :string
                            nullable ? GraphqlModelMapper::GeometryObjectCompare : !GraphqlModelMapper::GeometryObjectCompare
                        else
                            nullable ? GraphqlModelMapper::GeometryStringCompare : !GraphqlModelMapper::GeometryStringCompare
                    end
                else
                    nullable ? GraphqlModelMapper::StringCompare : !GraphqlModelMapper::StringCompare
                end
            end
        end

        # convert a database type to a GraphQL type
        # @param db_type [Symbol] the type returned by columns_hash[column_name].type
        # @param db_sql_type [String] the sql_type returned by columns_hash[column_name].sql_type
        # @return [GraphQL::ScalarType] a GraphQL type
        def self.convert_type db_type, db_sql_type="", nullable=true
            # because we are outside of a GraphQL define block we cannot use the types helper
            # we must refer directly to the built-in GraphQL scalar types
            case db_type
            when :integer
                nullable ? GraphQL::INT_TYPE : !GraphQL::INT_TYPE
            when :decimal, :float
                nullable ? GraphQL::FLOAT_TYPE : !GraphQL::FLOAT_TYPE
            when :boolean
                nullable ? GraphQL::BOOLEAN_TYPE : !GraphQL::BOOLEAN_TYPE
            when :date, :datetime
                nullable ? GraphqlModelMapper::DATE_TYPE : !GraphqlModelMapper::DATE_TYPE
            else
                case db_sql_type.to_sym #these are strings not symbols
                when :geometry, :multipolygon, :polygon
                    case db_type
                        when :string
                            nullable ? GraphqlModelMapper::GEOMETRY_OBJECT_TYPE : !GraphqlModelMapper::GEOMETRY_OBJECT_TYPE
                        else
                            nullable ? GraphqlModelMapper::GEOMETRY_STRING_TYPE : !GraphqlModelMapper::GEOMETRY_STRING_TYPE
                    end
                else
                    nullable ? GraphQL::STRING_TYPE : !GraphQL::STRING_TYPE
                end
            end
        end

        def self.get_compare_type db_type, db_sql_type="", nullable=true
            # because we are outside of a GraphQL define block we cannot use the types helper
            # we must refer directly to the built-in GraphQL scalar types
            case db_type
            when :integer
                nullable ? GraphQL::INT_TYPE : !GraphQL::INT_TYPE
            when :decimal, :float
                nullable ? GraphQL::FLOAT_TYPE : !GraphQL::FLOAT_TYPE
            when :boolean
                nullable ? GraphQL::BOOLEAN_TYPE : !GraphQL::BOOLEAN_TYPE
            when :date, :datetime
                nullable ? GraphqlModelMapper::DATE_TYPE : !GraphqlModelMapper::DATE_TYPE
            else
                case db_sql_type.to_sym #these are strings not symbols
                when :geometry, :multipolygon, :polygon
                    case db_type
                        when :string
                            nullable ? GraphqlModelMapper::GEOMETRY_OBJECT_TYPE : !GraphqlModelMapper::GEOMETRY_OBJECT_TYPE
                        else
                            nullable ? GraphqlModelMapper::GEOMETRY_STRING_TYPE : !GraphqlModelMapper::GEOMETRY_STRING_TYPE
                    end
                else
                    nullable ? GraphQL::STRING_TYPE : !GraphQL::STRING_TYPE
                end
            end
        end

        def self.get_property_enum_type(name, associations, db_fields, columns)
            model = name.classify.constantize
            property_enum_type_name = "#{GraphqlModelMapper.get_type_name(name)}PropertyEnum"
            if GraphqlModelMapper.defined_constant?(property_enum_type_name)
                property_enum_type = GraphqlModelMapper.get_constant(property_enum_type_name)
            else
                property_enum_type = GraphQL::EnumType.define do                    
                    #ensure type name is unique  so it does not collide with known types
                    name  property_enum_type_name
                    description "a property enum interface for the #{name} ActiveRecord model"
                    associations.sort_by(&:name).each do |reflection|
                        begin
                            klass = reflection.klass if !reflection.options[:polymorphic]
                            next if !(klass.public_methods.include?(:graphql_delete) || klass.public_methods.include?(:graphql_create) || klass.public_methods.include?(:graphql_update))
                        rescue
                            GraphqlModelMapper.logger.info("invalid relation #{reflection.name} specified on the #{name} model, the relation class does not exist")
                            next # most likely an invalid association without a class name, skip if other errors are encountered
                        end                    
                        if reflection.macro != :has_many
                            if reflection.options[:polymorphic] #not currently supported as an input type
                                #if GraphqlModelMapper.scan_for_polymorphic_associations
                                #    argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_polymorphic_type(reflection, name, type_sub_key: type_sub_key)}    
                                #end
                            else
                                #value(reflection.name, columns[f.to_s].type.to_s, value: "#{model.table_name}.#{f}") if [:integer, :string, :datetime, :boolean].include?(columns[f.to_s].type)
                            end 
                        end                
                    end if 1==0
                    
                    db_fields.sort.each  do |f|
                        target_type = GraphqlModelMapper::MapperType.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, false)
                        value(f, columns[f.to_s].type.to_s, value: "#{model.table_name}.#{f}") if [:integer, :string, :datetime, :boolean, :date].include?(columns[f.to_s].type)
                        #puts "#{model.table_name}.#{f} #{columns[f.to_s].type}" if model.table_name == "jobs"
                        #value(f, target_type.to_s, value: "#{model.table_name}.#{f}") if [GraphQL::INT_TYPE, GraphQL::STRING_TYPE, GraphqlModelMapper::DATE_TYPE, GraphQL::BOOLEAN_TYPE,GraphqlModelMapper::GEOMETRY_OBJECT_TYPE, GraphqlModelMapper::GEOMETRY_STRING_TYPE].include?(target_type)
                    end
                end
                GraphqlModelMapper.set_constant(property_enum_type_name, property_enum_type)
            end
            GraphqlModelMapper.get_constant(property_enum_type_name)
        end
    end
end    