module GraphqlModelMapper
    module MapperType
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
            foreign_keys: false, 
            primary_keys: false, 
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
            
            ret_type = GraphQL::InputObjectType.define do
                #ensure type name is unique  so it does not collide with known types
                name typename
                description "an input interface for the #{name} ActiveRecord model"
                # create GraphQL fields for each association
                associations.sort_by(&:name).each do |reflection|
                    begin
                        klass = reflection.klass if !reflection.options[:polymorphic]
                    rescue
                        GraphqlModelMapper.logger.info("invalid relation #{reflection.name} specified on the #{name} model, the relation class does not exist")
                        next # most likely an invalid association without a class name, skip if other errors are encountered
                    end                    
                    if reflection.macro == :has_many
                        argument reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_sub_key: type_sub_key).to_list_type} do
                            if GraphqlModelMapper.use_authorize
                                authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
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
                                    authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
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
                    argument f.to_sym, -> {GraphqlModelMapper.convert_type(columns[f.to_s].type, columns[f.to_s].sql_type, false)}
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
                authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
                access_type :read.to_s
 
                description "an output interface for the #{name} ActiveRecord model"
                # create GraphQL fields for each association
                associations.sort_by(&:name).each do |reflection|
                    begin
                        klass = reflection.klass if !reflection.options[:polymorphic]
                    rescue
                        GraphqlModelMapper.logger.info("invalid relation #{reflection.name} specified on the #{name} model, the relation class does not exist")
                        next # most likely an invalid association without a class name, skip if other errors are encountered
                    end                    
                    if reflection.macro == :has_many
                        if [:deep].include?(GraphqlModelMapper.nesting_strategy)
                            connection reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_connection_type(klass.name, GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_sub_key: type_sub_key))}, property: reflection.name.to_sym, max_page_size: GraphqlModelMapper.max_page_size do
                                if GraphqlModelMapper.use_authorize
                                    authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
                                    model_name klass.name
                                    access_type :read.to_s
                                end
                            end 
                        else
                            field reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_list_type(klass.name, GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_sub_key: type_sub_key))}, property: reflection.name.to_sym do
                                if GraphqlModelMapper.use_authorize
                                    authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
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
                                field reflection.name.to_sym, -> {GraphqlModelMapper::CustomType.const_get(custom_type_name)} 
                            elsif GraphqlModelMapper.scan_for_polymorphic_associations   
                                field reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_polymorphic_type(reflection, name)}, property: reflection.name.to_sym    
                            end 
                        else
                            field reflection.name.to_sym, -> {GraphqlModelMapper::MapperType.get_ar_object_with_params(klass.name, type_sub_key: type_sub_key)}, property: reflection.name.to_sym do
                                if GraphqlModelMapper.use_authorize
                                    authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
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
            end if type_sub_key == :output_type
            GraphqlModelMapper.set_constant(typename, ret_type) if !GraphqlModelMapper.defined_constant?(typename)
            ret_type
        end
    

        def self.get_polymorphic_type(reflection, model_name)
            type_name = "#{model_name}#{reflection.name.to_s.classify}UnionOutput"

            return GraphqlModelMapper.get_constant(type_name) if GraphqlModelMapper.defined_constant?(type_name)

            model = model_name.classify.constantize
            has_with_deleted = model.public_methods.include?(:with_deleted)
            parent_name = "#{reflection.name}_type"
            parent_classes = has_with_deleted ? model.with_deleted.select("distinct #{parent_name}").map{|m| m.send("#{parent_name}".to_sym)} :  model.select("distinct #{parent_name}").map{|m| m.send("#{parent_name}".to_sym)}
            types = []
            parent_classes.each do |p|
                types << self.get_ar_object_with_params(p, type_sub_key: :output_type)
            end

            ret_type = GraphQL::UnionType.define do
                name type_name
                description "UnionType for polymorphic association #{reflection.name} on #{model_name}"
                possible_types types
                resolve_type ->(obj, ctx) {
                    GraphqlModelMapper::MapperType.get_ar_object_with_params(obj.class.name)
                }
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
    

        def self.get_connection_type(model_name, output_type)
            connection_type_name = "#{GraphqlModelMapper.get_type_case(GraphqlModelMapper.get_type_name(model_name))}Connection"
            if GraphqlModelMapper.defined_constant?(connection_type_name)
                connection_type = GraphqlModelMapper.get_constant(connection_type_name)
            else
                connection_type = output_type.define_connection do
                    name connection_type_name
                    field :total, hash_key: :total do
                        type types.Int
                        resolve ->(obj, args, ctx) {
                            obj.nodes.limit(nil).count
                            #obj.nodes.length  
                        }
                    end
                end
                GraphqlModelMapper.set_constant(connection_type_name, connection_type)
            end
            return GraphqlModelMapper.get_constant(connection_type_name)
        end

        def self.get_list_type(model_name, output_type)
            list_type_name = "#{GraphqlModelMapper.get_type_case(GraphqlModelMapper.get_type_name(model_name))}List"     
            if GraphqlModelMapper.defined_constant?(list_type_name)
                list_type = GraphqlModelMapper.get_constant(list_type_name)
            else
                list_type = GraphQL::ObjectType.define do
                    name(list_type_name)
                
                    field :items, -> {output_type.to_list_type}, hash_key: :items do
                        argument :per_page, GraphQL::INT_TYPE
                        argument :page, GraphQL::INT_TYPE
                        resolve->(obj, args, ctx){
                            first_rec = nil
                            last_rec = nil
                            limit = GraphqlModelMapper.max_page_size.to_i
                            
                            if args[:per_page]
                                per_page = args[:per_page].to_i
                                raise GraphQL::ExecutionError.new("per_page must be greater than 0") if per_page < 1
                                raise GraphQL::ExecutionError.new("you requested more items than the maximum page size #{limit}, please reduce your requested per_page entry") if per_page > limit
                                limit = [per_page,limit].min
                            end
                            if args[:page]
                                page = args[:page].to_i
                                raise GraphQL::ExecutionError.new("page must be greater than 0") if page < 1
                                max_page = (obj.count/limit).ceil
                                raise GraphQL::ExecutionError.new("you requested page #{page} which is greater than the maximum number of pages #{max_page}") if page > max_page
                                obj = obj.offset((page-1)*limit)
                            end
                            begin
                                obj.limit(0).to_a
                            rescue ActiveRecord::StatementInvalid => e
                                raise GraphQL::ExecutionError.new(e.message.sub(" AND (1=1)", "").sub(" LIMIT 0", ""))
                            end
                            obj = obj.limit(limit)
                            obj
                        }
                    end
                    field :total, -> {GraphQL::INT_TYPE}, hash_key: :total do 
                        resolve->(obj,args, ctx){
                            obj.count
                        }
                    end
                end
                GraphqlModelMapper.set_constant(list_type_name, list_type)
            end
            GraphqlModelMapper.get_constant(list_type_name)
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