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
              authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
              model_name f[:model_name]
              access_type f[:access_type].to_s
            end
          end   
        end
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
              authorized ->(ctx, model_name, access_type) { GraphqlModelMapper.authorized?(ctx, model_name, access_type.to_sym) }
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
        {
          success: true
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
    field :id, !GraphQL::ID_TYPE do
      resolve -> (obj, args, ctx) {
        GraphqlModelMapper::Encryption.encode(GraphQL::Schema::UniqueWithinType.encode(GraphqlModelMapper::MapperType.graph_object(obj.class.name).name, obj.id))
      }  
    end 
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
            value.nil? ? nil :  Date.iso8601(value)
        rescue ArgumentError
            raise GraphQL::CoercionError, "cannot coerce `#{value.inspect}` to date"
        end
    end
    coerce_result ->(value, ctx) { value.nil? ? nil : value.iso8601 }
  end
  