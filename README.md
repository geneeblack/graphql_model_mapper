# graphql_model_mapper
This project is a work in progress and is in a pre-alpha state. Many thanks to @AndyKriger https://github.com/AndyKriger who initiated and shared the original idea on the GraphQL issue thread https://github.com/rmosolgo/graphql-ruby/issues/945. 

The graphql_model_mapper gem facilitates the generation of GraphQL objects based on the definition of your existing ActiveRecord models.

It has been tested on Rails 3.2, 4.1 and 5.0 using Ruby 2.1.10 and 2.2.8 

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'graphql_model_mapper'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install graphql_model_mapper

## Usage

Initially, you will not have any models exposed as GraphQL types. To expose a model you can add any/all of the following macro attributes to your model definition:

```ruby
graphql_query   # to generate a GraphQL query object (and associated GraphQL input/output types) for the model 
graphql_create  # to generate a GraphQL create mutation object (and its associated GraphQL input/output types) for the model
graphql_delete  # to generate a GraphQL delete mutation object (and its associated GraphQL input/output types) for the model
graphql_update  # to generate a GraphQL update mutation object (and its associated GraphQL input/output types) for the model
```

## Type options
The default input/output types generated for the model are based on the default settings (which may be overriden by initializing GraphqlModelMapper::GRAPHQL_DEFAULT_TYPES in your own initializer 

```ruby
#config/initializers/grapqhql_model_mapper_init.rb
GraphqlModelMapper::CustomType::GRAPHQL_DEFAULT_TYPES = {
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
}
```

or individually by using the 

```ruby
graphql_types
```

macro attribute on the model, passing the individual settings that differ from the defaults. These will be merged into the default values. i.e.

```ruby
graphql_types output_type: {
        excluded_attributes: [:crypted_password, :secret, :username],
        association_macro: :none, 
        foreign_keys: false,
        primary_keys: false
    },               
    input_type: {
        excluded_attributes: [:crypted_password, :secret, :username], 
        association_macro: :none,
        foreign_keys: false,
        primary_keys: false
    }
```

or you can initialize your own GRAPHQL_DEFAULT_TYPES constant for the model in an initializer, these settings will not be merged into the default settings, so you will need to fully elucidate the types

```ruby
#config/initializers/grapqhql_model_mapper_init.rb
GraphqlModelMapper::CustomType::[YOUR_MODEL_NAME_CLASSIFIED_AND_CAPITALIZED]_GRAPHQL_DEFAULT_TYPES = {
    input_type: {
        required_attributes: [], 
        excluded_attributes: [:crypted_password, :secret, :username], 
        allowed_attributes: [], 
        foreign_keys: false, 
        primary_keys: false, 
        validation_keys: false, 
        association_macro: :none, 
        source_nulls: false
    },
    output_type: {
        required_attributes: [], 
        excluded_attributes: [:crypted_password, :secret, :username], 
        allowed_attributes: [], 
        foreign_keys: false, 
        primary_keys: false, 
        validation_keys: false, 
        association_macro: :none, 
        source_nulls: false
    }
}
```

## Resolver Options

The query and mutation objects have a default resolver defined that may be sufficient for your needs (with the exception of the create mutation which simply validates the input and does not actually create the record). 

```ruby
def self.create_resolver(obj, inputs, ctx, model_name)
    if !GraphqlModelMapper.authorized?(ctx, model_name, :create)
        raise GraphQL::ExecutionError.new("error: unauthorized access: create '#{model_name.classify}'")
    end
    model = model_name.classify.constantize   
    item = model.new(inputs[model_name.downcase].to_h)
    begin
        if !item.valid?
        raise GraphQL::ExecutionError.new(item.errors.full_messages.join("; "))
        else
        raise GraphQL::ExecutionError.new("error: WIP, item not saved but is a valid '#{model_name.classify}'")
        #item.save!
        end
    end
    item
end
```

If you want to assign your own resolvers for your type you can override the default resolver for the type on the macro attribute in the following way:

```ruby
graphql_query resolver: -> (obj, inputs, ctx){ GraphqlModelMapper.log_resolve(ctx, args, generate_error: true) ) }
```

or create named methods on your model which will override the resolver (takes precedence over the default resolver AND the macro assigned resolver)

```ruby
def self.graphql_query_resolver(obj,args,ctx)
    # this method will log the info for the inputs(arguments)/outputs(fields) to the Rails logger as well as optionally generate an error containing the information
    # it can be called from any resolve method 
    GraphqlModelMapper.log_resolve(ctx, args, generate_error: true)
end

def self.graphql_create_resolver(obj,args,ctx)
end

def self.graphql_update_resolver(obj,args,ctx)
end

def self.graphql_delete_resolver(obj,args,ctx)
end
```

The method that you assign to the resolver should either be self contained or call a class method that accepts and orchestrates the parameters passed from GraphQL in the resolve. In this example the query resolver is calling a GraphqlModelMapper utility function to log the input parameters (args) and output type(s) (context.fields).

Another resolver option is to provide a resolver wrapper. This will wrap the inner resolves for queries and mutations with a wrapper method that you can use to accomplish global methodologies or to format results before or after your resolve method is called. They inherit from GraphqlModelMapper::Resolve::ResolveWrapper and can be declared in your initializer in the following manner:

```ruby
class GraphqlModelMapper::CustomType::QueryResolveWrapper < GraphqlModelMapper::Resolve::ResolveWrapper
    # @resolve_func is original resolve, either default resolve or overriden from model
    # you can insert other custom functionality required before or after the resolver is called
    def call(obj, args, ctx)
        puts "overidden query resolve wrapper"

        # custom methods to call before the resolve

        ret = @resolve_func.call(obj, args, ctx)

        # custom methods to call after the resolve

        # always return the result from the resolve or your custom formatted methods (complying with the expected return type) at the end of the wrapper call
        ret
    end
end 

class GraphqlModelMapper::CustomType::MutationResolveWrapper < GraphqlModelMapper::Resolve::ResolveWrapper
    def call(obj, args, ctx)
        puts "overidden mutation resolve wrapper"
        @resolve_func.call(obj, args, ctx)
    end
end
```

These are then passed to your Schema arguments 

```ruby
GraphqlModelMapper.Schema(mutation_resolve_wrapper: GraphqlModelMapper::CustomType::MutationResolveWrapper, query_resolve_wrapper: GraphqlModelMapper::CustomType::QueryResolveWrapper)
```

Some other attributes that you can set on the macro functions in addition to the input/output types and resolver are 

## graphql_query

```ruby
description:    # a short description of the query
scope_methods:  # scope methods available to be used in the query, these can be parameterized (must not be named parameters, must be accepted as string arguments and coerced in the method if needed) and must be written so that they valid in the presence of other tables which may be included in the associations
arguments:      # a list of argument definitions to override the default GraphQL arguments, if using your own arguments you will need to override the query resolver to act on those arguments 
```

Arguments should be a list of objects with the following attributes (*required)

    *name - displayed name of the attribute
    *type - GraphQL type of the attribute
    default - default argument value
    authorization - authorization level for the attribute (if GraphqlModelMapper.use_authorize = true this authorization will be compared to the authorized ability for the user on the model to which this attribute applies)

The default arguments handled by the default resolver and exposed on the query and delete mutations are:

```ruby
default_arguments =
[{:name=>:explain,  :type=>GraphQL::BOOLEAN_TYPE, :default=>nil, :authorization=>:manage},              # handled by the default resolver, outputs the top level sql for the operation
{:name=>:id,        :type=>GraphQL::INT_TYPE, :default=>nil},                                           # allows input of an global id for top level record selection for the model
{:name=>:ids,       :type=>GraphQL::INT_TYPE.to_list_type, :default=>nil},                              # allows input of an array of global ids for top level records selection for the model
{:name=>:item_id,   :type=>GraphQL::INT_TYPE, :default=>nil},                                           # allows input of a record id for top level record selection for the model
{:name=>:item_ids,  :type=>GraphQL::INT_TYPE.to_list_type, :default=>nil}                               # allows input of an array of record ids for top level records selection for the model
{:name=>:limit,     :type=>GraphQL::INT_TYPE, :default=>50},                                            # limits the number of records retuurned (defaults to 50 records)
{:name=>:offset,    :type=>GraphQL::INT_TYPE, :default=>nil},                                           # specifies an offset for the start of the records returned
{:name=>:order,     :type=>GraphQL::STRING_TYPE, :default=>nil, :authorization=>:manage},               # a string value that is passed to ActiveRecord query specifying the output order 
{:name=>:where,     :type=>GraphQL::STRING_TYPE.to_list_type, :default=>nil, :authorization=>:manage}]  # a string array for use in ActiveRecord query, can be a string or a query/value array to be used by the query ["model.id =? and model.date is not nul]", "1"]
{:name=>:scopes,    :type=>ModelScopeList, :default=>nil, :authorization=>:manage}]                    # a list of ModelScopeEnums exposed on the graphql_query/graphql_delete macro, :allowed_scopes and their optional arguments string array
```

## graphql_delete

    description:
    scope_methods:
    arguments:
    resolver:

## graphql_update
    
    description:
    resolver:

## graphql_create

    description:
    resolver:

## Optional Authorization

The schema has the capability to use the cancancan gem to enable authorized access to the query and mutation fields based on the models, if implemented it also will control the availability of the associations assigned to the model based on their underlying model authorization. This is an optional setup and is not required.  

```ruby
gem "cancancan", "~> 1.10"
```

Follow the setup for cancancan and create an app/model/ability.rb file to setup your access rights

```ruby
class Ability
    include CanCan::Ability

    def initialize(user)
        # Define abilities for the passed in user here. For example:
        #
        #   user ||= User.new # guest user (not logged in)
        #   if user.admin?
        #     can :manage, :all
        #   else
        #     can :read, :all
        #   end
        #
        # The first argument to `can` is the action you are giving the user
        # permission to do.
        # If you pass :manage it will apply to every action. Other common actions
        # here are :read, :create, :update and :destroy.
        #
        # The second argument is the resource the user can perform the action on.
        # If you pass :all it will apply to every resource. Otherwise pass a Ruby
        # class of the resource.
        #
        # The third argument is an optional hash of conditions to further filter the
        # objects.
        # For example, here the user can only update published articles.
        #
        #   can :update, Article, :published => true
        #
        # See the wiki for details:
        # https://github.com/CanCanCommunity/cancancan/wiki/Defining-Abilities


        user ||= User.new # guest user (not logged in)
        if user.is_admin?
            can :manage, :all
        else
            can :manage, [YourModelA] # this will allow access to :query, :create, :update, :delete GraphQL methods for defined models
            can :read,   [YourModelB] # this will allow access to :query GraphQL methods for defined models as well as allow read access to associations of that type
            can :create, [YourModelC] # this will allow access to :create GraphQL methods for defined models
            can :update, [YourModelD] # this will allow access to :update GraphQL methods for defined models
            can :delete, [YourModelE] # this will allow access to :delete GraphQL methods for defined models

        end

    end
end
```

GraphqlModelMapper requires an ability method on your current_user in order to check the context current_user's authorization to access a GraphQL objects model implementation.

```ruby
class User < ActiveRecord::Base
    def ability
        @ability ||= Ability.new(self)
    end

    ...
end
```

## Schema implementation

Once you have your models decorated with the graphql_query/graphql_update/graphql_create/graphql_delete attributes the next step is implementing your schema and adding it to your controller. For this example I am using a schema definition located at app/graphql/graphql_model_mapper_schema.rb. I have used https://github.com/exAspArk/graphql-errors to handle errors generated from the resolve methods. It is not required but it provides an easy way to setup error handling.

```ruby
#app/graphql/graphql_model_mapper_schema.rb
require 'graphql_model_mapper'

# these are options that can be passed to the schema initiation to enable query logging or for authorization setup
#
# nesting_strategy: can be :flat, :shallow or :deep
# type_case: can be :camelize, :underscore or :classify
# scan_for_polymorphic_associations: when true will automatically scan your tables for the types to use when it encounters polymorphic associations, this defaults to **false** because it is a high cost operation. It is recommended that you setup custom types to handle the polymorphic associations to avoid table scans during the schema build process. See the custom types section for additional guidance on this topic.

# default values are shown here
default_schema_options = {log_query_depth: false, log_query_complexity: false, use_backtrace: false, use_authorize: false, nesting_strategy: :deep, type_case: :camelize, max_page_size: 100, scan_for_polymorphic_associations: false, mutation_resolve_wrapper: nil, query_resolve_wrapper: nil, bidirectional_pagination: false, default_nodes_field: false}

GraphqlModelMapperSchema = GraphqlModelMapper.Schema(default_schema_options)
GraphQL::Errors.configure(GraphqlModelMapperSchema) do

  rescue_from ActiveRecord::StatementInvalid do |exception|
    GraphQL::ExecutionError.new(exception.message)
  end

  rescue_from ActiveRecord::RecordNotFound do |exception|
    GraphQL::ExecutionError.new(exception.message)
  end


  rescue_from ActiveRecord::RecordInvalid do |exception|
    GraphQL::ExecutionError.new(exception.message)
  end

  rescue_from StandardError do |exception|
    GraphQL::ExecutionError.new(exception.message)
  end
end
```

## Graphiql controller setup

I recommend that you install 

```ruby
gem "graphiql-rails"
```

so you may access and test your GraphQL queries. It is located at https://github.com/rmosolgo/graphiql-rails. Once you have graphiql-rails you can setup the route 

```ruby
#config/routes.rb
[YourApp]::Application.routes.draw do
  if Rails.env.development? || Rails.env.staging?   # you can restrict access to graphiql to specific environments here
    mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql"
  end

  post "/graphql", to: "graphql#execute"

  ....
end
```

you can then reference your previously assigned schema in `app/controllers/graphql_controller.rb`

```ruby
#app/controllers/graphql_controller.rb
class GraphqlController < ApplicationController
    def execute
        variables = ensure_hash(params[:variables])
        query = params[:query]
        operation_name = params[:operationName]
        context = {
            # Query context goes here, for example:
            current_user: current_user
        }

        begin
        if (logged_in?)# && current_user.is_admin?)
            Ability.new(current_user) if GraphqlModelMapper.use_authorize # set on GraphqlModelMapper.Schema initialization
        elsif Rails.env != "development"
            query = nil
        end
        result = GraphqlModelMapperSchema.execute(query, variables: variables, context: context, operation_name: operation_name, except: ExceptFilter)

        end
        render json: result
    end

    private
    # this class is exercised when use_authorize is true
    class ExceptFilter
        def self.call(schema_member, context)
            return false unless GraphqlModelMapper.use_authorize
            # true if field should be excluded, false if it should be included
            return false unless authorized_proc = schema_member.metadata[:authorized_proc]
            model_name = schema_member.metadata[:model_name]
            access_type = schema_member.metadata[:access_type]
            !authorized_proc.call(context, model_name, access_type)
        end
    end

    def ensure_hash(query_variables)
        if query_variables.blank?
        {}
        elsif query_variables.is_a?(String)
        JSON.parse(query_variables)
        else
        query_variables
        end
    end
end
```

## Custom attribute types
The functionality included in the type generation uses the base type reported by ActiveRecord for the definition of the Input/Output model field/argument types. These base types include:

    :integer -> GraphQL::INT_TYPE
    :decimal, :float -> GraphQL::FLOAT_TYPE
    :boolean -> GraphQL::BOOLEAN_TYPE
    :date, :datetime -> GraphqlModelMapper::DATE_TYPE
    :geometry, :multipolygon, :polygon -> GraphqlModelMapper::GEOMETRY_OBJECT_TYPE
    :string -> GraphQL::STRING_TYPE

In some cases this is not sufficient. In the case that you are using ActiveRecord Enums (Rails >= 4.1) or you have stuffed formatted data into a field that you would like to display in a custom way there is an option for you to define a custom type for input/output of that specialized data.

In order to support this functionality you will need to create an initializer for creation of your custom types. The naming convention will allow the GraphqlModelMapper to pickup your custom types for use in the generated schema in place of the default ActiveRecord db type.

Use the form "#{model_name.classified}#{db_column_name.classified}Attribute#{Input/Output}" to name your custom type in the following manner.

If your model name is "Job" and the attribute that you want to override the type is named "status", you will want to create a GraphQL object constant like the following:

```ruby
GraphqlModelMapper::CustomType::JobStatusAttributeInput
GraphqlModelMapper::CustomType::JobStatusAttributeOutput
```

in the following example I will show you how to create an override type for a Rails >=4.1 Enum value

given the following definition in a model named 'Job' with an enum type mapped to the 'status' attribute

```ruby
class Job < ApplicationRecord
    enum status: { applied:0, enrolled: 100, accepted: 200, rejected: 300, cancelled: 400}
end
```

to enable application of a custom type to handle the input/output of the AR enum value you would need to create custom types in an initilizer. In this case we will use config/initializers/graphql_model_mapper_init.rb to create those types.

If you do not need to intercept the values when the custom type is used in input/output you can simply assign a GraphQL enum to the custom type. (take note of the naming convention used in the last statement, since the custom type will be picked up by convention when the model types are built it is important that you follow the naming convention **exactly** to ensure your custom type is used, custom types should be defined and reside in the GraphqlModelMapper::CustomType namespace). Since we do not need to intercept the field/argument resolver/prepare for this type, both input and output can be directly assigned to the GraphQL enum type. **(this case is already handled by default in Rails >=4.1 so you will not need to establish a custom type for this built in support for Rails enums)**

**config/initializers/graphql_model_mapper_init.rb**

```ruby
#config/initializers/graphql_model_mapper_init.rb

GraphqlModelMapper::CustomType::JobStatusAttributeEnum = GraphQL::EnumType.define do
  name "JobStatusAttributeEnum"
  value("Applied", "", value: 'applied')
  value("Enrolled", "", value: 'enrolled')
  value("Accepted", "", value: 'accepted')
  value("Rejectd", "", value: 'rejected')
  value("Cancelled", "", value: 'cancelled')
end

GraphqlModelMapper::CustomType::JobStatusAttributeOutputType = GraphqlModelMapper::CustomType::JobStatusAttributeInputType = GraphqlModelMapper::CustomType::JobStatusAttributeEnumType
```

In the event that you need to customize the way in which your custom types are used at runtime you will need to fully declare the field and argument that will be used with your custom type. In this example I am declaring the Input and Output fully so that I can use additional functionality in the prepare/resolve methods.

**config/initializers/graphql_model_mapper_init.rb**

```ruby
#config/initializers/graphql_model_mapper_init.rb
GraphqlModelMapper::CustomType::JobStatusAttributeEnum = GraphQL::EnumType.define do
  name "JobStatusAttributeEnum"
  value("Applied", "", value: 'applied')
  value("Enrolled", "", value: 'enrolled')
  value("Accepted", "", value: 'accepted')
  value("Rejectd", "", value: 'rejected')
  value("Cancelled", "", value: 'cancelled')
end

GraphqlModelMapper::CustomType::JobStatusAttributeOutput = GraphQL::Field.define do
  name "JobStatusAttributeOutput"
  type(GraphqlModelMapper::CustomType::JobStatusAttributeEnum)
  description("testing")
  resolve ->(object, arguments, context) { 
    object.status 
  }
end

GraphqlModelMapper::CustomType::JobStatusAttributeInput = GraphQL::Argument.define do
  name "JobStatusAttributeInput"
  type (GraphqlModelMapper::CustomType::JobStatusAttributeEnum)
  prepare ->(value, ctx) do
    value
  end
end
```

once you have these types defined and have restarted your server you should be able to see the mapping to the custom type in your __schema__ view and be able to use the GraphQL enums for query and update.

To establish a custom type for a polymorphic association attribute on your model you will follow the same naming convention, but establish a GraphQL UnionType with interfaces that match the possible types that the polymorphic relation represent. (UnionTypes are not valid on input types, so they are only applicable to the output type)

Assuming you have a relation in your models resembling:

```ruby
class Car  < ActiveRecord::Base
  belongs_to :parent, :polymorphic => true
end

class Ford < ActiveRecord::Base
    has_many :cars, :as => :parent
end

class Chevy < ActiveRecord::Base
    has_many :cars, :as => :parent
end
```

you will then add the following to your initialization file for the custom type:

```ruby
GraphqlModelMapper::CustomType::CarParentUnionOutput = GraphQL::UnionType.define do
    name "CarParentUnionOutput"
    description "UnionType for polymorphic association parent on Car"
    possible_types [GraphqlModelMapper::CHEVYOUTPUT, GraphqlModelMapper::FORDOUTPUT]
    resolve_type ->(obj, ctx) {
        #the field resolve_type will dereference the correct type when queried using the GraphqlModelMapper::MapperType.graph_object utility method to return the correct type mapped to the model (this method could also be used in the possible_types declaration if prefferred over the use of the assigned contant)

        GraphqlModelMapper::MapperType.graph_object(obj.class.name)
}
end
```

when resolving the parent attribute in a query you will need to write the query to late resolve the type when the data is fetched:

    query {
        car{
            items {
                nodes {
                    parent {
                        ... on FordOutput{
                            id
                            model
                            ford_specific_attribute
                        }
                        
                        ... on ChevyOutput{
                            id
                            model
                            chevy_specific_attribute
                        }
                    }
                }
            }
        }
    } 

**Note: when querying the model, you will still use the underlying database field value for any custom type when using it in a 'where' argument since the query is sent directly to the db and has no knowlege of the Rails enum or other GraphQL custom types.**

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/geneeblack/graphql_model_mapper.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
