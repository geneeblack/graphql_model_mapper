module GraphqlModelMapper
    module MapperType
        def self.graphql_types(
            name: self.name,
            query: {},
            update: {},
            delete: {},
            create: {}
            )
            return GraphqlModelMapper.get_constant("#{name.upcase}_GRAPHQL_DEFAULT_TYPES") if GraphqlModelMapper.const_defined?("#{name.upcase}_GRAPHQL_DEFAULT_TYPES") 
            graphql_type = {}
            graphql_type[:query] = query
            graphql_type[:update] = update
            graphql_type[:delete] = delete
            graphql_type[:create] = create
            merged_graphql_type = self.graphql_default_types.deep_merge(graphql_type)
            GraphqlModelMapper.set_constant("#{name.upcase}_GRAPHQL_DEFAULT_TYPES", merged_graphql_type)

            merged_graphql_type
        end


        def self.get_ar_object_with_params(name, type_key: nil, type_sub_key: nil)
            self.get_ar_object(name, self.get_type_params(name, type_key: type_key, type_sub_key: type_sub_key))
        end
        
        def self.get_ar_object(name, 
            required_attributes: [], 
            excluded_attributes: [], 
            allowed_attributes: [],
            foreign_keys: false, 
            primary_keys: false, 
            validation_keys: false, 
            association_macro: nil, 
            source_nulls: true,
            type_key: nil,
            type_sub_key: nil)
        
            
            #typesuffix = method(__method__).parameters.map { |arg| eval arg[1].to_s }.hash.abs.to_i.to_s
            typesuffix = "#{type_key.to_s.classify}#{GraphqlModelMapper.underscore(type_sub_key.to_s)}".camelize
            typename = "#{GraphqlModelMapper.get_type_name(name)}#{typesuffix}"
            
            return GraphqlModelMapper.get_constant(typename) if GraphqlModelMapper.defined_constant?(typename)
        
            model = name.classify.constantize
        
            required_attributes = required_attributes.map(&:to_sym) | (validation_keys ? self.model_validation_keys(name) : [])
            
            columns = model.columns_hash
        
            # figure out which association fields we are exposing
            association_includes =  (model.reflect_on_all_associations(association_macro).map(&:name)).map(&:to_sym) - excluded_attributes 
        
            # find all relations for this model, skip ones where the association klass is invalid, as well as polymorphic associations, be cognizant of include/exclude arrays similar to dbfields
            associations = model.reflect_on_all_associations(association_macro).select{|t| begin t.klass rescue next end}.select{|t| !t.options[:polymorphic] && association_includes.include?(t.name.to_sym) } 
            # never show foreign keys for defined associations
            db_fields_never = foreign_keys ? [] : ( associations.map(&:association_foreign_key) + associations.map(&:options).select{|v| v.key?(:foreign_key) }.map {|x| x[:foreign_key]} ).uniq.map(&:to_sym)
                
            # figure out which database fields we are exposing
            allowed_attributes = allowed_attributes.count > 0 ? allowed_attributes.map(&:to_sym) : associations.map(&:name) + columns.keys.map(&:to_sym)
            allowed_associations = (associations.map(&:name) - excluded_attributes - db_fields_never) & allowed_attributes
            db_fields = (columns.keys.map(&:to_sym) - excluded_attributes - db_fields_never) & allowed_attributes
            associations = associations.select{|m| allowed_associations.include?(m.name)}
            enums = (Rails.version.split(".").first.to_i >= 4 && Rails.version.split(".").second.to_i >= 1) || (Rails.version.split(".").first.to_i >= 5) ? model.defined_enums.keys : [] 
            enum_values = (Rails.version.split(".").first.to_i >= 4 && Rails.version.split(".").second.to_i >= 1) || (Rails.version.split(".").first.to_i >= 5) ? model.defined_enums : [] 
            
            ret_type = GraphQL::InputObjectType.define do
                #ensure type name is unique  so it does not collide with known types
                name typename
                description "an input interface for the #{name} ActiveRecord model"
                # create GraphQL fields for each exposed database field
                db_fields.select{|s| (primary_keys && s.to_sym == :id)}.each do |f|
                    argument f.to_sym, -> {GraphqlModelMapper::MapperType.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, (source_nulls ? columns[f.to_s].null : true))}
                end       
                db_fields.select{|s| required_attributes.include?(s)}.each do |f|
                    argument f.to_sym, -> {GraphqlModelMapper.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, false)}
                end       
                # create GraphQL fields for each association
                associations.sort_by(&:name).each do |reflection|
                    begin
                        klass = reflection.klass
                    rescue
                        GraphqlModelMapper.logger.warning("invalid relation #{reflection.name} specified on the #{name} model, the relation class does not exist")
                        next # most likely an invalid association without a class name, skip if other errors are encountered
                    end                    
                    if reflection.macro == :has_many
                        argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_key: type_key, type_sub_key: type_sub_key).to_list_type} do
                            if GraphqlModelMapper.use_authorize
                                authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
                                model_name klass.name
                                access_type type_key.to_s
                            end
                        end   
                    else
                        argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_key: type_key, type_sub_key: type_sub_key)} do
                            if GraphqlModelMapper.use_authorize
                                authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
                                model_name klass.name
                                access_type type_key.to_s
                            end
                        end   
                    end                
                end
        
                db_fields.reject{|s| (primary_keys && s.to_sym == :id) || required_attributes.include?(s)}.sort.each do |f|
                    custom_type_name = "#{name.classify}#{f.to_s.classify}Attribute#{:input_type.to_s.classify}"
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
                description "an output interface for the #{name} ActiveRecord model"
                # create GraphQL fields for each exposed database field
                db_fields.select{|s| (primary_keys && s.to_sym == :id)}.each do |f|
                    #puts "source null #{f} #{source_nulls ? columns[f.to_s].null : true}"
                    field f.to_sym, -> {GraphqlModelMapper::MapperType.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, (source_nulls ? columns[f.to_s].null : true))}
                end       
                db_fields.select{|s| required_attributes.include?(s)}.sort.each do |f|
                    field f.to_sym, -> {GraphqlModelMapper::MapperType.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, false)}
                end       
            # create GraphQL fields for each association
                associations.sort_by(&:name).each do |reflection|
                    begin
                        klass = reflection.klass
                    rescue
                        GraphqlModelMapper.logger.warning("invalid relation #{reflection.name} specified on the #{name} model, the relation class does not exist")
                        next # most likely an invalid association without a class name, skip if other errors are encountered
                    end                    
                    if reflection.macro == :has_many
                        if [:deep].include?(GraphqlModelMapper.nesting_strategy) && type_key == :query
                            connection reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_key: type_key, type_sub_key: type_sub_key).connection_type} do
                                if GraphqlModelMapper.use_authorize
                                    authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
                                    model_name klass.name
                                    access_type :read.to_s
                                end
                            end 
                        else
                            field reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_key: type_key, type_sub_key: type_sub_key).to_list_type} do
                                if GraphqlModelMapper.use_authorize
                                    authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
                                    model_name klass.name
                                    access_type :read.to_s
                                end
                            end    
                        end
                    else
                        field reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_key: type_key, type_sub_key: type_sub_key)} do
                            if GraphqlModelMapper.use_authorize
                                authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
                                model_name klass.name
                                access_type :read.to_s
                            end
                        end   
                    end
                end                        
                db_fields.reject{|s| (primary_keys && s.to_sym == :id) || required_attributes.include?(s)}.sort.each do |f|
                    custom_type_name = "#{name.classify}#{f.to_s.classify}Attribute#{:output_type.to_s.classify}"
                    if GraphqlModelMapper::CustomType.const_defined?(custom_type_name)
                        field f.to_sym, GraphqlModelMapper::CustomType.const_get(custom_type_name)
                    else
                        if enums.include?(f.to_s)
                            field f.to_sym, -> {GraphqlModelMapper::MapperType.get_enum_object(name, enum_values[f.to_s], f.to_s)}
                        else
                            field f.to_sym, -> {GraphqlModelMapper::MapperType.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, (source_nulls ? columns[f.to_s].null : true))}
                        end
                    end
                end
            end if type_sub_key == :output_type
            GraphqlModelMapper.set_constant(typename, ret_type) if !GraphqlModelMapper.defined_constant?(typename)
            ret_type
        end
    
        def self.get_type_params(name, type_key: nil, type_sub_key: nil)
            model = name.classify.constantize
            if model.public_methods.include?(:graphql_types)
                params = model.graphql_types
            else
                params = self.graphql_default_types
            end
            #puts params
            if !type_key.nil?
                if params.keys.include?(type_key.to_sym)
                params = params[type_key.to_sym]
                if !type_sub_key.nil?
                    if params.keys.include?(type_sub_key.to_sym)
                    params = params[type_sub_key.to_sym]
                    else
                    params = nil
                    end
                end
                else
                params = nil
                end
            end
            params 
        end
    
        def self.graphql_default_types(
            query: {
            input_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: false,
                type_key: :query,
                type_sub_key: :input_type
            },
            output_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: false,
                type_key: :query,
                type_sub_key: :output_type
            }
            },
            update: {
            input_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: false,
                type_key: :update,
                type_sub_key: :input_type
            },
            output_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: true,
                type_key: :update,
                type_sub_key: :output_type
            }
            },
            delete: {
            input_type: {
                required_attributes: [:id], 
                excluded_attributes: [], 
                allowed_attributes: [:id], 
                foreign_keys: false, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: false,
                type_key: :delete,
                type_sub_key: :input_type
            },
            output_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: false, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: true,
                type_key: :delete,
                type_sub_key: :output_type
            }
            },
            create: {
            input_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: false, 
                validation_keys: false, 
                association_macro: :has_many, 
                source_nulls: false,
                type_key: :create,
                type_sub_key: :input_type
            },
            output_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: true,
                type_key: :create,
                type_sub_key: :output_type
            }
            })
            return GraphqlModelMapper.get_constant("GRAPHQL_DEFAULT_TYPES") if GraphqlModelMapper.const_defined?("GRAPHQL_DEFAULT_TYPES") 
                
            graphql_type = {}
            graphql_type[:query] = query
            graphql_type[:update] = update
            graphql_type[:delete] = delete
            graphql_type[:create] = create
        
            GraphqlModelMapper.set_constant("GRAPHQL_DEFAULT_TYPES", graphql_type)
            graphql_type
        end
    
        def self.model_validation_keys(name)
            model = name.classify.constantize
            validation_attributes = model.validators.select{|m| m.is_a?(ActiveModel::Validations::PresenceValidator) && !m.options[:if]}.map(&:attributes).flatten
            model.reflect_on_all_associations.select{|p| validation_attributes.include?(p.name) }.map(&:foreign_key).map(&:to_sym)  | validation_attributes & model.columns_hash.keys.map(&:to_sym)
        end

        def self.get_enum_object(model_name, enum, enum_name)
            enum_values = enum.keys
            type_name = "#{model_name.classify}#{enum_name.classify}EnumType"
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
    end
end    