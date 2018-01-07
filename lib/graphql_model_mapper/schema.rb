module GraphqlModelMapper
    def self.Schema(log_query_depth: false, log_query_complexity: false, use_backtrace: false, use_authorize: false, nesting_strategy: :deep, type_case: :camelize, max_page_size: 100, scan_for_polymorphic_associations: false, mutation_resolve_wrapper: nil, query_resolve_wrapper: nil, bidirectional_pagination: false, default_nodes_field: false, handle_errors: false, secret_token: nil)

      return GraphqlModelMapper.get_constant("GraphqlModelMapperSchema".upcase) if GraphqlModelMapper.defined_constant?("GraphqlModelMapperSchema".upcase)
      GraphqlModelMapper.use_authorize = use_authorize
      GraphqlModelMapper.nesting_strategy = nesting_strategy
      GraphqlModelMapper.type_case = type_case
      GraphqlModelMapper.max_page_size = max_page_size
      GraphqlModelMapper.scan_for_polymorphic_associations = scan_for_polymorphic_associations
      GraphqlModelMapper.default_nodes_field = default_nodes_field
      GraphqlModelMapper.bidirectional_pagination = bidirectional_pagination
      GraphqlModelMapper.handle_errors = handle_errors
      
      if query_resolve_wrapper && query_resolve_wrapper < GraphqlModelMapper::Resolve::ResolveWrapper
        GraphqlModelMapper.query_resolve_wrapper = query_resolve_wrapper
      else
        GraphqlModelMapper.query_resolve_wrapper = GraphqlModelMapper::Resolve::ResolveWrapper
      end
        
      if mutation_resolve_wrapper && mutation_resolve_wrapper < GraphqlModelMapper::Resolve::ResolveWrapper
        GraphqlModelMapper.mutation_resolve_wrapper = mutation_resolve_wrapper
      else
        GraphqlModelMapper.mutation_resolve_wrapper = GraphqlModelMapper::Resolve::ResolveWrapper
      end

      if secret_token
        GraphqlModelMapper.secret_token = secret_token
      end


      GraphQL::Relay::ConnectionType.bidirectional_pagination = GraphqlModelMapper.bidirectional_pagination
      GraphQL::Relay::ConnectionType.default_nodes_field = GraphqlModelMapper.default_nodes_field
      
      #if GraphqlModelMapper.use_authorize
        metadata_definitions = {
          authorized: ->(field, authorized_proc) { field.metadata[:authorized_proc] = authorized_proc },
          model_name: GraphQL::Define.assign_metadata_key(:model_name),
          access_type: GraphQL::Define.assign_metadata_key(:access_type)
        }
        GraphQL::Field.accepts_definitions(metadata_definitions)
        GraphQL::Argument.accepts_definitions(metadata_definitions)
        GraphQL::ObjectType.accepts_definitions(metadata_definitions)
        GraphQL::BaseType.accepts_definitions(metadata_definitions)
        #end

      schema = GraphQL::Schema.define do
        use GraphQL::Backtrace if use_backtrace
        instrument :query, QueryInstrumentation
        default_max_page_size max_page_size.to_i
        mutation GraphqlModelMapper.MutationType
        query GraphqlModelMapper.QueryType
                
        resolve_type ->(type, obj, ctx) {
          return GraphqlModelMapper::UNAUTHORIZED if !GraphqlModelMapper.authorized?(ctx, obj.class.name)
          #raise GraphQL::ExecutionError.new("unauthorized access: #{obj.class.name}") if !GraphqlModelMapper.authorized?(ctx, obj.class.name)
          GraphqlModelMapper.get_constant("#{obj.class.name}Output".upcase)
        }

        # Create UUIDs by joining the type name & ID, then base64-encoding it
        id_from_object ->(object, type_definition, context) {
          begin
            GraphqlModelMapper::Encryption.encode(GraphQL::Schema::UniqueWithinType.encode(type_definition.name, object.id))
          rescue
            ""
          end
        }

        object_from_id ->(id, context) {
          type_name, item_id = nil
          begin
            type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(GraphqlModelMapper::Encryption.decode(id))
          rescue => e
            raise GraphQL::ExecutionError.new("incorrect global id: unable to resolve id: #{e.message}")            
          end
          
          type = GraphqlModelMapper.get_constant(type_name.upcase)
          raise GraphQL::ExecutionError.new("unknown type for id: #{id}") if type.nil?
          authorized_proc = type.metadata[:authorized_proc]
          model_name = type.metadata[:model_name]
          access_type = type.metadata[:access_type]
          
    
          return GraphqlModelMapper::UNAUTHORIZED if GraphqlModelMapper.use_authorize && (!authorized_proc || !authorized_proc.call(context, model_name, access_type))
          #raise GraphQL::ExecutionError.new("unauthorized access for id: #{id}") if !authorized_proc.call(context, model_name, access_type)
          model = model_name.to_s.classify.constantize
          model.unscoped.find(item_id)
        }
      end

      schema.query_analyzers << GraphQL::Analysis::QueryDepth.new { |query, depth| Rails.logger.info("[******GraphqlModelMapper Query Depth] #{depth}") } if log_query_depth
      schema.query_analyzers << GraphQL::Analysis::QueryComplexity.new { |query, complexity| Rails.logger.info("[******GraphqlModelMapper Query Complexity] #{complexity}")} if log_query_complexity
      GraphQL::Errors.configure(schema) do
        rescue_from ActiveRecord::RecordNotFound do |exception|
          nil
        end
      
        rescue_from ActiveRecord::StatementInvalid do |exception|
          GraphQL::ExecutionError.new(exception.message)
        end

        rescue_from ActiveRecord::RecordInvalid do |exception|
          GraphQL::ExecutionError.new(exception.record.errors.full_messages.join("\n"))
        end
      
        rescue_from StandardError do |exception|
          GraphQL::ExecutionError.new(exception.message)
        end

        rescue_from do |exception|
          GraphQL::ExecutionError.new(exception.message)
        end
      end if GraphqlModelMapper.handle_errors && GraphQL.const_defined?("Errors")

      GraphqlModelMapper.set_constant("GraphqlModelMapperSchema".upcase, schema)
      GraphqlModelMapper.get_constant("GraphqlModelMapperSchema".upcase)
    end


    def self.QueryType
      return GraphQL::ObjectType.define do
        name 'Query'
        # create queries for each AR model object
        field :node, GraphQL::Relay::Node.field do
          description "Fetches an object given its globally unique ID"
          argument :ep, GraphQL::STRING_TYPE
        end

        field :nodes, GraphQL::Relay::Node.plural_field do
          description "Fetches a list of objects given a list of globally unique IDs"
        end


        GraphqlModelMapper.schema_queries.each do |f|
          field f[:name], f[:field]  do
            if GraphqlModelMapper.use_authorize
              authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_field_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true }
              model_name f[:model_name]
              access_type f[:access_type].to_s
            end
          end   
        end

        #field :jobSearch, function: -> { GraphqlModelMapper::Resolve.get_model_search2("Job") }

      end
    end

    def self.MutationType
      return GraphQL::ObjectType.define do
        name 'Mutation'

        field :login, GraphqlModelMapper::LOGIN.field
        field :logout, GraphqlModelMapper::LOGOUT.field
        
        GraphqlModelMapper.schema_mutations.each do |f|
          field f[:name], f[:field]  do
            if GraphqlModelMapper.use_authorize
              authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.use_graphql_field_restriction ? GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) : true }
              model_name  f[:model_name]
              access_type f[:access_type].to_s
            end
          end
        end   
      end
    end
  end

  GraphqlModelMapper::LOGIN = GraphQL::Relay::Mutation.define do
    name 'Login'
    description ''
    input_field :username, !GraphQL::STRING_TYPE
    input_field :password, !GraphQL::STRING_TYPE
    return_field :success, GraphQL::BOOLEAN_TYPE

    resolve -> (obj, args, ctx){
      ctx[:current_user] = User.authenticate(args[:user_name], args[:password])
      {
        success: logged_in?
      }
    }
  end

  GraphqlModelMapper::LOGOUT = GraphQL::Relay::Mutation.define do
    name 'Logout'
    description ''
    return_field :success, GraphQL::BOOLEAN_TYPE    
    resolve -> (obj, args, ctx){
      {
        success: true
      }
    }
  end

  GraphqlModelMapper::UNAUTHORIZED = GraphQL::ObjectType.define do
    name "UnAuthorized"
    description "this type is returned when no access is allowed to the original requested type"
    field :message, GraphQL::STRING_TYPE do
      resolve -> (obj, args, ctx) {
        "you do not have authorization to access the requested type"
      }
    end
    implements GraphQL::Relay::Node.interface
    field :id, !GraphQL::ID_TYPE, property: :id do
      resolve -> (obj, args, ctx) {
        if obj.respond_to?(:id)
          GraphqlModelMapper::Encryption.encode(GraphQL::Schema::UniqueWithinType.encode(GraphqlModelMapper::MapperType.graph_object(obj.class.name).name, obj.id))
        else
          #TODO : see if the original id can be sent here
          ""
        end
      }  
    end 
  end


  GraphqlModelMapper::SortOrderEnum = GraphQL::EnumType.define do
    name "SortOrderEnum"
    description "allows selection of ascending descending"
    value("ascending", "asc", value: "ASC")
    value("descending", "desc", value: "DESC")
    value("noOp", "operation placeholder, no operation will be performed on this item", value:"")
  end

  GraphqlModelMapper::StringCompareEnum = GraphQL::EnumType.define do
    name "StringCompareEnum"
    description "String comparison operators"
    value("lessThan", "less than")
    value("greaterThan", "greater than")
    value("equalTo", "equal to")
    value("notEqualTo", "not equal to")
    value("lessThanOrEqualTo", "less than or equal to")
    value("greaterThanOrEqualTo", "greater than or equal to")
    value("contains", "contains")
    value("notContain", "contains")
    value("isNull", "is null")
    value("notNull", "is not null")
    value("noOp", "operation placeholder, no operation will be performed on this item")
  end

  GraphqlModelMapper::BooleanCompareEnum = GraphQL::EnumType.define do
    name "BooleanCompareEnum"
    description "String comparison operators"
    value("isTrue", " = 1")
    value("isFalse", " = 0")
    value("notNull", "is not null")
    value("noOp", "operation placeholder, no operation will be performed on this item")
  end

  GraphqlModelMapper::IntCompareEnum = GraphQL::EnumType.define do
    name "IntCompareEnum"
    description "String comparison operators"
    value("lessThan", "less than")
    value("greaterThan", "greater than")
    value("equalTo", "equal to")
    value("notEqualTo", "not equal to")
    value("lessThanOrEqualTo", "less than or equal to")
    value("greaterThanOrEqualTo", "greater than or equal to")
    value("isNull", "is null")
    value("notNull", "is not null")
    value("noOp", "operation placeholder, no operation will be performed on this item")
  end

  GraphqlModelMapper::DateCompareEnum = GraphQL::EnumType.define do
    name "DateCompareEnum"
    description "String comparison operators"
    value("lessThan", "less than")
    value("greaterThan", "greater than")
    value("equalTo", "equal to")
    value("notEqualTo", "not equal to")
    value("lessThanOrEqualTo", "less than or equal to")
    value("greaterThanOrEqualTo", "greater than or equal to")
    value("isNull", "is null")
    value("notNull", "is not null")
    value("noOp", "operation placeholder, no operation will be performed on this item")
  end

  GraphqlModelMapper::FloatCompareEnum = GraphQL::EnumType.define do
    name "FloatCompareEnum"
    description "String comparison operators"
    value("lessThan", "less than")
    value("greaterThan", "greater than")
    value("equalTo", "equal to")
    value("notEqualTo", "not equal to")
    value("lessThanOrEqualTo", "less than or equal to")
    value("greaterThanOrEqualTo", "greater than or equal to")
    value("isNull", "is null")
    value("notNull", "is not null")
    value("noOp", "operation placeholder, no operation will be performed on this item")
  end

  GraphqlModelMapper::GeometryObjectCompareEnum = GraphQL::EnumType.define do
    name "GeometryObjectCompareEnum"
    description "String comparison operators"
    value("lessThan", "less than")
    value("greaterThan", "greater than")
    value("equalTo", "equal to")
    value("notEqualTo", "not equal to")
    value("lessThanOrEqualTo", "less than or equal to")
    value("greaterThanOrEqualTo", "greater than or equal to")
    value("isNull", "is null")
    value("notNull", "is not null")
    value("noOp", "operation placeholder, no operation will be performed on this item")
  end

  GraphqlModelMapper::GeometryStringCompareEnum = GraphQL::EnumType.define do
    name "GeometryStringCompareEnum"
    description "String comparison operators"
    value("lessThan", "less than")
    value("greaterThan", "greater than")
    value("equalTo", "equal to")
    value("notEqualTo", "not equal to")
    value("lessThanOrEqualTo", "less than or equal to")
    value("greaterThanOrEqualTo", "greater than or equal to")
    value("isNull", "is null")
    value("notNull", "is not null")
    value("noOp", "operation placeholder, no operation will be performed on this item")
  end

  GraphqlModelMapper::JobIntGroup = GraphQL::ObjectType.define do
    name "JobGroup"
    field :key, [GraphQL::INT_TYPE]
    field :count, GraphQL::INT_TYPE
    field :sum, GraphQL::INT_TYPE
    field :min, GraphQL::INT_TYPE
    field :max, GraphQL::INT_TYPE
    field :items, -> { Job.graphql_query }, max_page_size: GraphqlModelMapper.max_page_size do 
      resolve -> (obj, args, ctx) {
        limit = GraphqlModelMapper.max_page_size
        raise GraphQL::ExecutionError.new("you have requested more items than the maximum page size #{limit}") if obj.length > limit && (args[:first].to_i > limit || args[:last].to_i > limit)
        obj
      }
    end
    field :groups, [GraphqlModelMapper::JobIntGroup]
  end

  GraphqlModelMapper::JobStringGroup = GraphQL::ObjectType.define do
    name "JobGroup"
    field :key, [GraphQL::STRING_TYPE]
    field :count, GraphQL::INT_TYPE
    field :min, GraphQL::STRING_TYPE
    field :max, GraphQL::STRING_TYPE
    field :items, -> {  Job.graphql_query }, max_page_size: GraphqlModelMapper.max_page_size do 
      resolve -> (obj, args, ctx) {
        limit = GraphqlModelMapper.max_page_size
        raise GraphQL::ExecutionError.new("you have requested more items than the maximum page size #{limit}") if obj.length > limit && (args[:first].to_i > limit || args[:last].to_i > limit)
        obj
      }
    end
  end
  
  GraphqlModelMapper::StringCompare = GraphQL::InputObjectType.define do
    name "StringCompare"
    argument :compare, GraphqlModelMapper::StringCompareEnum
    argument :value, GraphQL::STRING_TYPE
  end
  GraphqlModelMapper::IntCompare = GraphQL::InputObjectType.define do
    name "IntCompare"
    argument :compare, GraphqlModelMapper::IntCompareEnum
    argument :value, GraphQL::INT_TYPE
  end
  GraphqlModelMapper::FloatCompare = GraphQL::InputObjectType.define do
    name "FloatCompare"
    argument :compare, GraphqlModelMapper::FloatCompareEnum
    argument :value, GraphQL::FLOAT_TYPE
  end
  GraphqlModelMapper::BooleanCompare = GraphQL::InputObjectType.define do
    name "BooleanCompare"
    argument :compare, GraphqlModelMapper::BooleanCompareEnum
    argument :value, GraphQL::BOOLEAN_TYPE
  end
  GraphqlModelMapper::DateCompare = GraphQL::InputObjectType.define do
    name "DateCompare"
    argument :compare, GraphqlModelMapper::DateCompareEnum
    argument :value, GraphqlModelMapper::DATE_TYPE
  end
  GraphqlModelMapper::GeometryObjectCompare = GraphQL::InputObjectType.define do
    name "GeometryObjectCompare"
    argument :compare, GraphqlModelMapper::GeometryObjectCompareEnum
    argument :value, GraphqlModelMapper::GEOMETRY_STRING_TYPE
  end
  GraphqlModelMapper::GeometryStringCompare = GraphQL::InputObjectType.define do
    name "GeometryStringCompare"
    argument :compare, GraphqlModelMapper::GeometryStringCompareEnum
    argument :value, GraphqlModelMapper::GEOMETRY_OBJECT_TYPE
  end

  

  
  GraphqlModelMapper::GEOMETRY_OBJECT_TYPE = GraphQL::ScalarType.define do
    name "GeometryObject"
    description "The Geometry scalar type enables the serialization of Geometry data"
    require 'geo_ruby/geojson' if !defined?(GeoRuby).nil?

    coerce_input ->(value, ctx) do
        begin
            if value.nil? 
              nil 
            elsif !defined?(GeoRuby::GeojsonParser).nil?
              GeoRuby::SimpleFeatures::Geometry.from_geojson(value)
            elsif !defined?(RGeo::GeoJSON).nil?
              RGeo::GeoJSON.decode(value, json_parser: :json)
            else 
              raise ArgumentError
            end
        rescue ArgumentError
            raise GraphQL::CoercionError, "cannot coerce `#{value.inspect}` to json"
        end
    end
    coerce_result ->(value, ctx) { (value.nil? ? "" : (defined?(GeoRuby) == "constant" && value.kind_of?(GeoRuby::SimpleFeatures::Geometry) ? value.to_json : (defined?(RGeo) == "constant" && defined?(RGeo::GeoJSON) == "constant" && RGeo::Geos.is_capi_geos?(value) ? RGeo::GeoJSON.encode(value).to_json : value))) }
  end

  
  GraphqlModelMapper::GEOMETRY_STRING_TYPE = GraphQL::ScalarType.define do
    name "GeometryString"
    description "The Geometry scalar type enables the serialization of Geometry data"
    require 'geo_ruby/geojson' if !defined?(GeoRuby).nil?

    coerce_input ->(value, ctx) do
        begin
            if value.nil? 
              nil 
            elsif !defined?(GeoRuby::GeojsonParser).nil?
              GeoRuby::SimpleFeatures::Geometry.from_geojson(value).as_wkt 
            elsif !defined?(RGeo::GeoJSON).nil?
              RGeo::GeoJSON.decode(value, json_parser: :json).as_text
            else 
              raise ArgumentError
            end
        rescue ArgumentError
            raise GraphQL::CoercionError, "cannot coerce `#{value.inspect}` to json"
        end
    end
    coerce_result ->(value, ctx) { (value.nil? ? "" : (defined?(GeoRuby) == "constant" && value.kind_of?(GeoRuby::SimpleFeatures::Geometry) ? value.to_json : (defined?(RGeo) == "constant" && defined?(RGeo::GeoJSON) == "constant" && RGeo::Geos.is_capi_geos?(value) ? RGeo::GeoJSON.encode(value).to_json : value))) }
  end

  GraphqlModelMapper::DATE_TYPE = GraphQL::ScalarType.define do
    name "Date"
    description "The Date scalar type enables the serialization of date data to/from iso8601"
  
    coerce_input ->(value, ctx) do
        begin
            value.nil? ? nil : DateTime.iso8601(value).to_s
        rescue ArgumentError
            raise GraphQL::CoercionError, "cannot coerce `#{value.inspect}` to ISO 8601 date (YYYY-MM-DDThh:mm:ss+00:00 or YYYY-MM-DDThh:mm:ssZ or YYYYMMDDThhmmss5346Z )"
        end
    end
    coerce_result ->(value, ctx) { 
      value.nil? ? nil : value.iso8601 
    }
  end
  

  module QueryInstrumentation
    module_function
  
    # Log the time of the query
    def before_query(query)
      Rails.logger.info("Query: #{query.query_string}")
      Rails.logger.info("Query begin: #{Time.now.to_i}")
    end
  
    def after_query(query)
      Rails.logger.info("Query: #{query.query_string}")
      Rails.logger.info("Query end: #{Time.now.to_i}")
    end
  end